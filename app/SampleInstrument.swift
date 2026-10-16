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

/// One held voice, preloaded PCM, no file I/O when a key is pressed.
@MainActor
final class SampleInstrument {
    private let engine: AVAudioEngine
    private let voice = AVAudioPlayerNode()
    private let speed = AVAudioUnitVarispeed()
    private(set) var sample: InstrumentSample?
    private var generation = 0
    let meter = InstrumentMeter()
    var onFinished: (() -> Void)?
    var gain: Float = 0.25 { didSet { voice.volume = gain } }

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(voice); engine.attach(speed)
        let meter = self.meter
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in meter.update(buffer) }
    }
    func install(_ sample: InstrumentSample) {
        stop()
        engine.stop()
        engine.disconnectNodeOutput(voice)
        engine.disconnectNodeOutput(speed)
        engine.connect(voice, to: speed, format: sample.buffer.format)
        engine.connect(speed, to: engine.mainMixerNode, format: sample.buffer.format)
        self.sample = sample
    }
    func play(note: Int, root: Int) throws {
        guard let sample else { throw AudioError.invalid("先にサンプルを楽器へ取り込んでください。") }
        let rate = NotePitch.rate(note: note, root: root)
        guard (0.25...4).contains(rate) else { throw AudioError.invalid("演奏できる音域は基準音から上下2オクターブです。") }
        stop()
        speed.rate = rate
        voice.volume = gain
        if !engine.isRunning { engine.prepare(); try engine.start() }
        let token = generation
        voice.scheduleBuffer(sample.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.onFinished?()
            }
        }
        voice.play()
    }
    func stop() { generation += 1; voice.stop() }
    func shutdown() { stop(); engine.stop(); sample = nil }
}
