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
        precondition(asset.peaks.count == 2 && asset.peaks[0].count == 115200)
        precondition((asset.peaks[0].max() ?? 0) > 0.1)
        precondition(asset.peaks[0][1920] > asset.peaks[0][108800])
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
        var editor = WaveformEditor(frameCount: 384000, sampleRate: 48000)
        editor.select(from: 0.75, to: 0.25)
        precondition(editor.selection == AudioSelection(startFrame: 96000, endFrame: 288000))
        let originalSelection = editor.selection
        editor.setZoom(4, around: 0.5)
        precondition(editor.visibleRange == 0.375..<0.625)
        editor.pan(to: 1)
        precondition(editor.visibleRange == 0.75..<1)
        precondition(editor.selection == originalSelection)
        editor.fitSelection()
        precondition(editor.visibleRange.contains(0.25) && editor.visibleRange.upperBound >= 0.75)
        editor.setZoom(100, around: -1)
        precondition(editor.zoom == 32 && editor.visibleRange.lowerBound == 0)
        editor.setZoom(0.25, around: 1)
        precondition(editor.visibleRange == 0..<1)
        editor.select(from: -1, to: 2)
        precondition(editor.selection?.frameCount == 384000)
        editor.select(from: 0.5, to: 0.5)
        precondition(editor.selection == nil)
        editor.select(from: 0, to: 1.0 / 384000)
        precondition(editor.selection?.frameCount == 1)
        editor.clearSelection()
        precondition(editor.selection == nil)

        let clip = root.appendingPathComponent("selection.caf")
        let selected = AudioSelection(startFrame: 12345, endFrame: 65432)
        try SelectionAudio.write(source: demo, selection: selected, to: clip)
        let output = try AVAudioFile(forReading: clip)
        let input = try AVAudioFile(forReading: demo)
        precondition(output.length == selected.frameCount && output.processingFormat.channelCount == 2)
        precondition(output.processingFormat.sampleRate == input.processingFormat.sampleRate)
        let expected = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(selected.frameCount))!
        let actual = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(selected.frameCount))!
        input.framePosition = selected.startFrame
        try input.read(into: expected)
        try output.read(into: actual)
        precondition(actual.frameLength == expected.frameLength)
        for channel in 0..<2 {
            for frame in 0..<Int(actual.frameLength) {
                precondition(actual.floatChannelData![channel][frame] == expected.floatChannelData![channel][frame])
            }
        }
        for invalid in [AudioSelection(startFrame: -1, endFrame: 10),
                        AudioSelection(startFrame: 5, endFrame: 5),
                        AudioSelection(startFrame: 0, endFrame: 384001)] {
            do { try SelectionAudio.write(source: demo, selection: invalid, to: root.appendingPathComponent("invalid.caf")); fatalError("Invalid range accepted") } catch {}
        }
        try SelectionAudio.write(source: mono, selection: AudioSelection(startFrame: 44099, endFrame: 44100), to: root.appendingPathComponent("one-frame.caf"))
        let oneFrame = try AVAudioFile(forReading: root.appendingPathComponent("one-frame.caf"))
        precondition(oneFrame.length == 1)
        print("PASS: reversed/clamped/one-frame selection, zoom/pan/fit invariants, exact selected audio across chunks, invalid ranges, EOF")
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
            model.select(from: 0.125, to: 0.25)
            model.zoom(by: 4)
            precondition(model.editor.zoom == 4)
            await model.playSelection()
            precondition(model.playing && model.playingSelection && model.position == 1)
            try await Task.sleep(nanoseconds: 100_000_000)
            model.refreshPlaybackState()
            precondition(model.position >= 1 && model.position < 2)
            model.toggle()
            precondition(!model.playing)
            let paused = model.position
            try await Task.sleep(nanoseconds: 100_000_000)
            model.refreshPlaybackState()
            precondition(model.position == paused)
            model.toggle()
            try await Task.sleep(nanoseconds: 1_200_000_000)
            model.refreshPlaybackState()
            precondition(!model.playing && model.position == 2)
            model.toggle()
            precondition(model.playing && model.position == 1)
            model.clearSelection()
            precondition(!model.playing && !model.playingSelection && model.editor.selection == nil)
            model.select(from: 0.2, to: 0.3)
            await model.playSelection()
            model.seek(0.5)
            precondition(!model.playingSelection && !model.playing && model.position == 4)
            precondition(model.editor.selection != nil)
            print("PASS: selection-only playback, pause/resume, exact end, replay, clear and seek during preview")
            await model.load(broken)
            precondition(model.error != nil && model.asset?.url == demo)
            await model.load(mono)
            precondition(model.error == nil && model.asset?.channels == 1)
            precondition(model.editor.selection == nil && model.editor.zoom == 1)
            model.gainDB = -24
            model.seek(1)
            model.toggle()
            precondition(model.playing)
            model.stop()
            print("PASS: load, play, pause, seek, stop, failed-load preservation, replace mono, gain, replay at end")
        }
    }
}
