import Foundation
import AVFoundation

enum SamplePreparationTests {
    static func run() throws {
        let source: [[Float]] = [[0.25, -0.5, 0.1, 0.3], [-0.125, 0.25, -0.05, -0.15]]
        let dry = SamplePreparationSettings(normalize: false, targetDB: -3, fadeInMS: 0, fadeOutMS: 0)
        let unchanged = try SamplePreparationProcessor.process(source, sampleRate: 24000, settings: dry)
        precondition(unchanged.channels == source && unchanged.gainDB == 0)
        let aligned = try SamplePreparationProcessor.process(source, sampleRate: 24000,
            settings: SamplePreparationSettings(normalize: true, targetDB: -6, fadeInMS: 0, fadeOutMS: 0))
        precondition(abs(Double(aligned.resultPeak) - pow(10, -6.0/20)) < 1e-6)
        for i in source[0].indices { precondition(abs(aligned.channels[1][i] + aligned.channels[0][i] / 2) < 1e-7) }
        let faded = try SamplePreparationProcessor.process([Array(repeating: 0.5, count: 100)], sampleRate: 10000,
            settings: SamplePreparationSettings(normalize: false, targetDB: -3, fadeInMS: 1, fadeOutMS: 2))
        precondition(faded.channels[0][0] == 0 && faded.channels[0][99] == 0)
        precondition(faded.channels[0][10] == 0.5 && faded.channels[0][79] == 0.5)
        precondition(faded.channels[0][1] < faded.channels[0][8] && faded.channels[0][81] > faded.channels[0][98])
        let short = try SamplePreparationProcessor.process([[0.5]], sampleRate: 24000,
            settings: SamplePreparationSettings(normalize: false, targetDB: -3, fadeInMS: 250, fadeOutMS: 250))
        precondition(short.channels == [[0.5]])
        let silent = try SamplePreparationProcessor.process([[0,0]], sampleRate: 24000, settings: .init())
        precondition(silent.resultPeak == 0 && silent.gainDB == 0)
        let quiet = try SamplePreparationProcessor.process([[0.000001, -0.000001]], sampleRate: 24000,
            settings: SamplePreparationSettings(normalize: true, targetDB: -3, fadeInMS: 0, fadeOutMS: 0))
        precondition(quiet.boostLimited && abs(quiet.gainDB-24) < 1e-9)
        for bad in [[[Float.nan]], [[Float.infinity]], [[Float]()] , [[1], [1,2]]] {
            do { _ = try SamplePreparationProcessor.process(bad, sampleRate: 24000, settings: dry); preconditionFailure("Invalid PCM accepted") }
            catch { }
        }
        do { _ = try SamplePreparationProcessor.process(source, sampleRate: 0, settings: dry); preconditionFailure("Invalid rate accepted") }
        catch { }
        do { _ = try SamplePreparationProcessor.process(source, sampleRate: 24000, settings: .init(targetDB: .nan)); preconditionFailure("Invalid settings accepted") }
        catch { }

        // Real WAV and production instrument round trip without an audio engine/device.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-PreparationTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("demo.wav")
        try DemoAudio.write(to: input)
        let originalBytes = try Data(contentsOf: input)
        let sample = try InstrumentSample.load(url: input)
        let prepared = try SamplePreparationAudio.render(sample, settings: .init())
        defer { try? FileManager.default.removeItem(at: prepared.directory) }
        let afterBytes = try Data(contentsOf: input)
        precondition(afterBytes == originalBytes)
        precondition(prepared.sample.selection == sample.selection && prepared.sample.buffer.frameLength == sample.buffer.frameLength)
        let file = try AVAudioFile(forReading: prepared.preparedURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        for channel in prepared.report.channels.indices {
            let actual = Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
            precondition(actual == prepared.report.channels[channel])
        }
        let saved = dir.appendingPathComponent("prepared.sfinstrument")
        let loop = SampleLoop(endFrame: Int64(sample.buffer.frameLength))
        try InstrumentDocument.save(sample: prepared.sample, rootNote: 57, envelope: .standard, loop: loop, to: saved)
        let restored = try InstrumentDocument.load(saved)
        defer { try? FileManager.default.removeItem(at: restored.directory) }
        precondition(restored.rootNote == 57 && restored.loop == loop && restored.sample.buffer.frameLength == sample.buffer.frameLength)
        for channel in prepared.report.channels.indices {
            let actual = Array(UnsafeBufferPointer(start: restored.sample.buffer.floatChannelData![channel], count: Int(restored.sample.buffer.frameLength)))
            precondition(actual == prepared.report.channels[channel])
        }
        print("PASS: sample normalization/fades, linked stereo, invalid input, demo WAV and instrument round trip")
    }
}
