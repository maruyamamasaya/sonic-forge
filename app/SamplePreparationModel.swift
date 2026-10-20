import AVFoundation
import Combine

struct PreparedSampleAudio {
    let sample: InstrumentSample
    let report: PreparedSamplePCM
    let directory: URL
    var originalURL: URL { directory.appendingPathComponent("original.wav") }
    var preparedURL: URL { directory.appendingPathComponent("prepared.wav") }
}

enum SamplePreparationAudio {
    static func render(_ source: InstrumentSample, settings: SamplePreparationSettings) throws -> PreparedSampleAudio {
        guard let input = source.buffer.floatChannelData else { throw AudioError.invalid("音源を読み込めません。") }
        let count = Int(source.buffer.frameLength)
        let channels = (0..<Int(source.buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: input[$0], count: count)) }
        let report = try SamplePreparationProcessor.process(channels, sampleRate: source.buffer.format.sampleRate, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.buffer.format, frameCapacity: source.buffer.frameLength),
              let output = buffer.floatChannelData else { throw AudioError.invalid("加工結果のメモリを確保できません。") }
        buffer.frameLength = source.buffer.frameLength
        for channel in report.channels.indices {
            report.channels[channel].withUnsafeBufferPointer { output[channel].update(from: $0.baseAddress!, count: count) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-SamplePreparation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try write(source.buffer, to: directory.appendingPathComponent("original.wav"))
            try Task.checkCancellation()
            try write(buffer, to: directory.appendingPathComponent("prepared.wav"))
            return PreparedSampleAudio(sample: InstrumentSample(buffer: buffer, name: source.name, selection: source.selection), report: report, directory: directory)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    private static func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        var settings = buffer.format.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMIsFloatKey] = true
        settings[AVLinearPCMBitDepthKey] = 32
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}

@MainActor final class SamplePreparationModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum Audition { case original, prepared }
    @Published private(set) var busy = false
    @Published private(set) var result: PreparedSampleAudio?
    @Published private(set) var audition: Audition?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var player: AVAudioPlayer?

    func prepare(_ source: InstrumentSample, settings: SamplePreparationSettings) {
        cancel()
        let id = generation
        busy = true; error = nil
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { try SamplePreparationAudio.render(source, settings: settings) }
            do {
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard let self, generation == id, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: prepared.directory); return
                }
                result = prepared; busy = false; task = nil
            } catch {
                guard let self, generation == id else { return }
                busy = false; task = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func preview(_ kind: Audition) {
        stop()
        guard !busy, let result else { return }
        do {
            let replacement = try AVAudioPlayer(contentsOf: kind == .original ? result.originalURL : result.preparedURL)
            replacement.volume = Float(pow(10, -12.0 / 20))
            replacement.delegate = self
            guard replacement.prepareToPlay(), replacement.play() else { throw AudioError.invalid("試聴を開始できません。") }
            player = replacement; audition = kind; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func stop() { player?.stop(); player = nil; audition = nil }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; busy = false; stop()
        if let result { try? FileManager.default.removeItem(at: result.directory) }
        result = nil
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            stop()
        }
    }
}
