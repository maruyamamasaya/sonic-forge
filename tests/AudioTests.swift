import Foundation
import AVFoundation

@main
struct AudioTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForgeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = root.appendingPathComponent("demo.wav")
        try DemoAudio.write(to: demo)
        let asset = try AudioAsset.load(demo, isDemo: true)
        precondition(asset.duration == 8 && asset.channels == 2 && asset.sampleRate == 48000 && asset.bitDepth == 16)
        precondition(asset.peaks.count == 2 && asset.peaks[0].count == 1800)
        precondition((asset.peaks[0].max() ?? 0) > 0.1)
        precondition(asset.peaks[0][30] > asset.peaks[0][1700])
        precondition(timeLabel(62.345) == "01:02.345")
        // A different-rate mono Float WAV exercises the real import/conversion path.
        let mono = root.appendingPathComponent("mono.wav")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            let file = try AVAudioFile(forWriting: mono, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
            buffer.frameLength = 44100
            for i in 0..<44100 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100) * 0.2) }
            try file.write(from: buffer)
        }
        let monoAsset = try AudioAsset.load(mono)
        precondition(monoAsset.channels == 1 && monoAsset.sampleRate == 44100 && monoAsset.bitDepth == 32)
        precondition(abs(monoAsset.duration - 1) < 0.001)
        let broken = root.appendingPathComponent("broken.wav")
        try Data("not a wave".utf8).write(to: broken)
        do { _ = try AudioAsset.load(broken); fatalError("Invalid WAV accepted") } catch {}
        let missing = root.appendingPathComponent("missing.wav")
        do { _ = try AudioAsset.load(missing); fatalError("Missing file accepted") } catch {}
        print("PASS: demo synthesis, waveform, duration, stereo PCM16, mono Float32, time formatting, corrupt/missing files")
        if CommandLine.arguments.contains("--playback") {
            let model = PlayerModel()
            defer { model.cleanup() }
            await model.load(demo)
            precondition(model.asset != nil && model.error == nil)
            model.toggle()
            try await Task.sleep(nanoseconds: 200_000_000)
            precondition(model.playing)
            model.toggle()
            precondition(!model.playing)
            model.seek(0.5)
            precondition(abs(model.position - 4) < 0.01)
            model.stop()
            precondition(model.position == 0 && !model.playing)
            await model.load(broken)
            precondition(model.error != nil && model.asset?.url == demo)
            await model.load(mono)
            precondition(model.error == nil && model.asset?.channels == 1)
            model.gainDB = -24
            model.seek(1)
            model.toggle()
            precondition(model.playing)
            model.stop()
            print("PASS: load, play, pause, seek, stop, failed-load preservation, replace mono, gain, replay at end")
        }
    }
}
