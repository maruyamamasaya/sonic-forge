import Foundation
import AVFoundation

struct InstrumentSample {
    let buffer: AVAudioPCMBuffer
    let name: String
    let selection: AudioSelection
    var duration: Double { Double(buffer.frameLength) / buffer.format.sampleRate }

    static func load(url: URL, selection: AudioSelection? = nil) throws -> InstrumentSample {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let range = selection ?? AudioSelection(startFrame: 0, endFrame: file.length)
        guard range.startFrame >= 0, range.endFrame <= file.length, range.frameCount > 0,
              (1...2).contains(file.processingFormat.channelCount) else {
            throw AudioError.invalid("楽器に取り込む範囲が無効です。")
        }
        guard Double(range.frameCount) / file.processingFormat.sampleRate <= 30,
              range.frameCount * Int64(file.processingFormat.channelCount) * 4 <= 64 * 1024 * 1024 else {
            throw AudioError.invalid("最初のサンプラーでは30秒・64 MB以内の範囲を使用できます。波形で短い範囲を選択してください。")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(range.frameCount)) else {
            throw AudioError.invalid("楽器のメモリを確保できませんでした。")
        }
        file.framePosition = range.startFrame
        guard let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384),
              let destination = buffer.floatChannelData else { throw AudioError.invalid("楽器のメモリを確保できませんでした。") }
        var offset = 0
        while offset < Int(range.frameCount) {
            try file.read(into: chunk, frameCount: AVAudioFrameCount(min(16384, Int(range.frameCount) - offset)))
            guard chunk.frameLength > 0, let input = chunk.floatChannelData else { throw AudioError.invalid("楽器の音源を読み込めませんでした。") }
            for channel in 0..<Int(file.processingFormat.channelCount) {
                destination[channel].advanced(by: offset).update(from: input[channel], count: Int(chunk.frameLength))
            }
            offset += Int(chunk.frameLength)
        }
        buffer.frameLength = AVAudioFrameCount(offset)
        return InstrumentSample(buffer: buffer, name: url.lastPathComponent, selection: range)
    }
}

/// Frame offsets in the installed sample; end is exclusive.
struct SampleLoop: Codable, Equatable {
    var enabled = false
    var startFrame: Int64 = 0
    var endFrame: Int64
    var crossfadeFrames: Int64 = 0
    private enum CodingKeys: String, CodingKey { case enabled, startFrame, endFrame, crossfadeFrames }
    init(enabled: Bool = false, startFrame: Int64 = 0, endFrame: Int64, crossfadeFrames: Int64 = 0) {
        self.enabled = enabled; self.startFrame = startFrame; self.endFrame = endFrame
        self.crossfadeFrames = crossfadeFrames
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        startFrame = try values.decode(Int64.self, forKey: .startFrame)
        endFrame = try values.decode(Int64.self, forKey: .endFrame)
        crossfadeFrames = try values.decodeIfPresent(Int64.self, forKey: .crossfadeFrames) ?? 0
    }
    func isValid(frameCount: Int64, sampleRate: Double = .infinity) -> Bool {
        startFrame >= 0 && endFrame <= frameCount && endFrame > startFrame && endFrame - startFrame >= (enabled ? 2 : 1)
            && crossfadeFrames >= 0 && crossfadeFrames <= (endFrame - startFrame) / 2
            && Double(crossfadeFrames) <= sampleRate * 0.1
    }
}

enum NotePitch {
    static func rate(note: Int, root: Int) -> Float { Float(pow(2, Double(note - root) / 12)) }
    static func name(_ note: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[note % 12] + String(note / 12 - 1)
    }
}

/// The audio callback never waits for the UI reader.
final class InstrumentMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var left: Float = -60
    private var right: Float = -60
    func update(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        func level(_ channel: Int) -> Float {
            var sum: Float = 0
            for frame in 0..<Int(buffer.frameLength) { let x = data[channel][frame]; sum += x * x }
            return max(-60, min(0, 10 * log10(max(1e-12, sum / Float(buffer.frameLength)))))
        }
        let a = level(0), b = level(min(1, Int(buffer.format.channelCount) - 1))
        guard lock.try() else { return }
        left = a; right = b
        lock.unlock()
    }
    func read() -> [Float] { lock.lock(); defer { lock.unlock() }; return [left, right] }
}

/// Render-owned envelope and PCM cursor. UI operations use a short lock; the
/// audio callback only tries the lock, never waits, and performs no file I/O.
final class InstrumentVoice: @unchecked Sendable {
    private let lock = NSLock()
    private var sample: InstrumentSample?
    private var position = 0
    private var envelope = ADSREnvelope()
    private var rate = 1.0
    private var active = false
    private var loop: SampleLoop?

    func install(_ sample: InstrumentSample) {
        lock.lock(); defer { lock.unlock() }
        self.sample = sample; active = false; envelope.stop(); position = 0
    }
    func trigger(_ parameters: ADSRParameters, rate: Double, loop: SampleLoop? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.loop = loop.flatMap { value in
            guard let sample, value.enabled, value.isValid(frameCount: Int64(sample.buffer.frameLength), sampleRate: sample.buffer.format.sampleRate) else { return nil }
            return value
        }
        self.rate = rate; position = 0; envelope.trigger(parameters); active = true
    }
    func release() { lock.lock(); defer { lock.unlock() }; envelope.noteOff() }
    func stop() { lock.lock(); defer { lock.unlock() }; active = false; envelope.stop() }
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func render(frames: AVAudioFrameCount, output: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        guard lock.try() else { return }
        defer { lock.unlock() }
        guard active, let sample, let pcm = sample.buffer.floatChannelData else { return }
        for frame in 0..<Int(frames) {
            if let loop, position >= Int(loop.endFrame) { position = Int(loop.startFrame + loop.crossfadeFrames) }
            guard position < Int(sample.buffer.frameLength) else { active = false; envelope.stop(); break }
            let amplitude = envelope.next(sampleRate: sample.buffer.format.sampleRate * rate)
            if envelope.stage == .idle { active = false; break }
            for channel in 0..<min(buffers.count, Int(sample.buffer.format.channelCount)) {
                var value = pcm[channel][position]
                if let loop, loop.crossfadeFrames > 0,
                   position >= Int(loop.endFrame - loop.crossfadeFrames) {
                    let offset = position - Int(loop.endFrame - loop.crossfadeFrames)
                    let blend = Float(offset + 1) / Float(loop.crossfadeFrames)
                    value = value * (1 - blend) + pcm[channel][Int(loop.startFrame) + offset] * blend
                }
                buffers[channel].mData?.assumingMemoryBound(to: Float.self)[frame] = value * amplitude
            }
            position += 1
        }
    }
}

@MainActor
final class SampleInstrument {
    private let engine: AVAudioEngine
    private var source: AVAudioSourceNode?
    private let speed = AVAudioUnitVarispeed()
    private let voice = InstrumentVoice()
    private(set) var sample: InstrumentSample?
    private var awaitingCompletion = false
    let meter = InstrumentMeter()
    var onFinished: (() -> Void)?
    var gain: Float = 0.25 { didSet { engine.mainMixerNode.outputVolume = gain } }
    var isSounding: Bool { voice.isActive }

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(speed)
        let meter = self.meter
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in meter.update(buffer) }
    }
    func install(_ sample: InstrumentSample) {
        stop(); engine.stop()
        if let source { engine.detach(source) }
        engine.disconnectNodeOutput(speed)
        voice.install(sample)
        let voice = self.voice
        let source = AVAudioSourceNode(format: sample.buffer.format) { _, _, count, output in
            voice.render(frames: count, output: output)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: speed, format: sample.buffer.format)
        engine.connect(speed, to: engine.mainMixerNode, format: sample.buffer.format)
        self.source = source
        self.sample = sample
    }
    func play(note: Int, root: Int, envelope: ADSRParameters = .standard, loop: SampleLoop? = nil) throws {
        guard sample != nil else { throw AudioError.invalid("先にサンプルを楽器へ取り込んでください。") }
        let rate = NotePitch.rate(note: note, root: root)
        guard (0.25...4).contains(rate), envelope.isValid else { throw AudioError.invalid("音域またはADSRの設定が無効です。") }
        if let loop, let sample, !loop.isValid(frameCount: Int64(sample.buffer.frameLength), sampleRate: sample.buffer.format.sampleRate) {
            throw AudioError.invalid("ループ範囲が無効です。")
        }
        stop()
        speed.rate = rate
        engine.mainMixerNode.outputVolume = gain
        if !engine.isRunning { engine.prepare(); try engine.start() }
        voice.trigger(envelope, rate: Double(rate), loop: loop)
        awaitingCompletion = true
    }
    func noteOff() { voice.release() }
    func refreshCompletion() {
        if awaitingCompletion && !voice.isActive { awaitingCompletion = false; onFinished?() }
    }
    func stop() { awaitingCompletion = false; voice.stop() }
    func shutdown() { stop(); engine.stop(); sample = nil }
}
