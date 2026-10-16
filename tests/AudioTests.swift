import Foundation
import AVFoundation

@main
struct AudioTests {
    @MainActor static func main() async throws {
        EnvelopeTests.run()
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
        let exported = root.appendingPathComponent("exported.wav")
        let sourceBytes = try Data(contentsOf: demo)
        try WAVExport.write(source: demo, selection: selected, to: exported)
        let imported = try AudioAsset.load(exported)
        precondition(imported.channels == 2 && imported.sampleRate == 48000 && imported.bitDepth == 32)
        precondition(abs(imported.duration - Double(selected.frameCount) / 48000) < 0.000001)
        let wave = try AVAudioFile(forReading: exported)
        let waveBuffer = AVAudioPCMBuffer(pcmFormat: wave.processingFormat, frameCapacity: AVAudioFrameCount(selected.frameCount))!
        try wave.read(into: waveBuffer)
        precondition(wave.length == selected.frameCount)
        for channel in 0..<2 {
            for frame in 0..<Int(waveBuffer.frameLength) {
                precondition(waveBuffer.floatChannelData![channel][frame] == expected.floatChannelData![channel][frame])
            }
        }
        let protected = root.appendingPathComponent("existing.wav")
        try Data("keep existing file".utf8).write(to: protected)
        do { try WAVExport.write(source: demo, selection: AudioSelection(startFrame: -1, endFrame: 10), to: protected); fatalError("Invalid export accepted") } catch {}
        let preserved = try Data(contentsOf: protected)
        precondition(preserved == Data("keep existing file".utf8))
        for alias in [demo, root.appendingPathComponent("symlink.wav"), root.appendingPathComponent("hardlink.wav")] {
            if alias.lastPathComponent == "symlink.wav" { try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: demo) }
            if alias.lastPathComponent == "hardlink.wav" { try FileManager.default.linkItem(at: demo, to: alias) }
            do { try WAVExport.write(source: demo, selection: selected, to: alias); fatalError("Source overwrite accepted") } catch {}
        }
        let unchanged = try Data(contentsOf: demo)
        precondition(unchanged == sourceBytes)
        try WAVExport.write(source: mono, selection: AudioSelection(startFrame: 100, endFrame: 1100), to: protected)
        let monoExport = try AudioAsset.load(protected)
        precondition(monoExport.channels == 1 && monoExport.sampleRate == 44100 && monoExport.bitDepth == 32)
        let blocked = root.appendingPathComponent("blocked.wav")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        do { try WAVExport.write(source: demo, selection: selected, to: blocked); fatalError("Directory overwrite accepted") } catch {}
        var isDirectory: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: blocked.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(!leftovers.contains { $0.hasPrefix(".sonicforge-export-") })
        precondition(NotePitch.rate(note: 60, root: 60) == 1)
        precondition(NotePitch.rate(note: 72, root: 60) == 2)
        precondition(NotePitch.rate(note: 48, root: 60) == 0.5)
        precondition(abs(NotePitch.rate(note: 61, root: 60) - 1.0594631) < 0.00001)
        precondition(NotePitch.name(60) == "C4" && NotePitch.name(57) == "A3")
        let instrumentPart = try InstrumentSample.load(url: demo, selection: selected)
        precondition(Int64(instrumentPart.buffer.frameLength) == selected.frameCount)
        for channel in 0..<2 {
            for frame in 0..<Int(instrumentPart.buffer.frameLength) {
                precondition(instrumentPart.buffer.floatChannelData![channel][frame] == expected.floatChannelData![channel][frame])
            }
        }
        do { _ = try InstrumentSample.load(url: demo, selection: AudioSelection(startFrame: 5, endFrame: 4)); fatalError("Invalid instrument range") } catch {}
        let originalCopy = root.appendingPathComponent("independent-source.wav")
        try FileManager.default.copyItem(at: demo, to: originalCopy)
        let savedEnvelope = ADSRParameters(attack: 0.12, decay: 0.34, sustain: 0.56, release: 0.78)
        let documentSample = try InstrumentSample.load(url: originalCopy, selection: selected)
        let documentURL = root.appendingPathComponent("My Instrument.sfinstrument")
        try InstrumentDocument.save(sample: documentSample, rootNote: 64, envelope: savedEnvelope, to: documentURL)
        try FileManager.default.removeItem(at: originalCopy)
        let restored = try InstrumentDocument.load(documentURL)
        defer { try? FileManager.default.removeItem(at: restored.directory) }
        precondition(restored.rootNote == 64 && restored.sample.name == documentSample.name && restored.envelope == savedEnvelope)
        precondition(restored.sample.buffer.frameLength == documentSample.buffer.frameLength)
        precondition(restored.sample.buffer.format.sampleRate == documentSample.buffer.format.sampleRate)
        for channel in 0..<2 {
            for frame in 0..<Int(restored.sample.buffer.frameLength) {
                precondition(restored.sample.buffer.floatChannelData![channel][frame] == documentSample.buffer.floatChannelData![channel][frame])
            }
        }
        let documentBytes = try Data(contentsOf: documentURL)
        let json = try JSONSerialization.jsonObject(with: documentBytes) as! [String: Any]
        let invalidDocument = root.appendingPathComponent("invalid.sfinstrument")
        for bad in ["version", "rootNote", "sampleWAV"] {
            var badJSON = json
            badJSON[bad] = bad == "sampleWAV" ? "not base64" : 999
            try JSONSerialization.data(withJSONObject: badJSON).write(to: invalidDocument)
            do { _ = try InstrumentDocument.load(invalidDocument); fatalError("Invalid archive accepted") } catch {}
        }
        var legacyJSON = json
        legacyJSON["version"] = 1
        legacyJSON.removeValue(forKey: "envelope")
        let legacyURL = root.appendingPathComponent("legacy.sfinstrument")
        try JSONSerialization.data(withJSONObject: legacyJSON).write(to: legacyURL)
        let legacy = try InstrumentDocument.load(legacyURL)
        defer { try? FileManager.default.removeItem(at: legacy.directory) }
        precondition(legacy.envelope == .legacy && legacy.rootNote == 64)
        for sustain in [-0.1, 1.1] {
            var invalid = json
            invalid["envelope"] = ["attack": 0.1, "decay": 0.1, "sustain": sustain, "release": 0.1]
            try JSONSerialization.data(withJSONObject: invalid).write(to: invalidDocument)
            do { _ = try InstrumentDocument.load(invalidDocument); fatalError("Invalid ADSR accepted") } catch {}
        }
        print("PASS: ADSR v2 persistence, legacy v1 sound compatibility, invalid envelope rejection")
        let monoDocument = root.appendingPathComponent("Mono.sfinstrument")
        try InstrumentDocument.save(sample: InstrumentSample.load(url: mono), rootNote: 60, to: monoDocument)
        let restoredMono = try InstrumentDocument.load(monoDocument)
        defer { try? FileManager.default.removeItem(at: restoredMono.directory) }
        precondition(restoredMono.sample.buffer.format.channelCount == 1 && restoredMono.sample.buffer.format.sampleRate == 44100)
        // Replacing a saved document must also be a valid round trip.
        try InstrumentDocument.save(sample: documentSample, rootNote: 57, to: documentURL)
        let replacedDocument = try InstrumentDocument.load(documentURL)
        defer { try? FileManager.default.removeItem(at: replacedDocument.directory) }
        precondition(replacedDocument.rootNote == 57)
        print("PASS: self-contained instrument save/open after source deletion, root and all samples, mono, overwrite, corrupt/version/root rejection")
        print("PASS: root note naming, semitone/octave ratios, instrument selection sample equality and invalid range")
        print("PASS: WAV export/reimport, exact frames/samples, mono/stereo, overwrite, original/symlink/hardlink protection, failure preservation and cleanup")
        print("PASS: reversed/clamped/one-frame selection, zoom/pan/fit invariants, exact selected audio across chunks, invalid ranges, EOF")
        print("PASS: demo synthesis, waveform, duration, stereo PCM16, mono Float32, time formatting, corrupt/missing files")
        if CommandLine.arguments.contains("--playback") {
            let model = PlayerModel()
            defer { model.cleanup() }
            await model.load(demo)
            precondition(model.asset != nil && model.error == nil)
            model.select(from: 0.125, to: 0.25)
            let exportSelection = model.editor.selection!
            let modelExport = root.appendingPathComponent("model-export.wav")
            model.gainDB = -40
            await model.export(asset: model.asset!, selection: exportSelection, to: modelExport)
            precondition(model.exportMessage != nil && !model.busy && model.editor.selection == exportSelection)
            precondition(model.asset?.url == demo)
            await model.load(modelExport)
            precondition(model.error == nil && model.asset?.duration == 1 && model.asset?.bitDepth == 32)
            model.toggle()
            precondition(model.playing)
            model.stop()
            await model.load(demo)
            print("PASS: model export with attenuated monitor gain, reimport and playback")
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
            model.rootNote = 60
            await model.prepareInstrument(useSelection: false)
            precondition(model.instrumentSample != nil, model.error ?? "No sample; busy=\(model.busy)")
            model.playNote(60)
            precondition(model.activeNote == 60)
            try await Task.sleep(nanoseconds: 150_000_000)
            model.refreshPlaybackState()
            precondition(model.levels[0] > -60)
            model.playNote(72)
            precondition(model.activeNote == 72)
            model.releaseNote(60)
            precondition(model.activeNote == 72)
            model.releaseNote(72)
            precondition(model.activeNote == nil)
            model.playNote(60)
            model.rootNote = 57
            precondition(model.activeNote == nil)
            await model.load(demo, demo: true)
            model.select(from: 0, to: 0.025)
            await model.prepareInstrument()
            precondition(abs(model.instrumentSample!.duration - 0.2) < 0.00001)
            model.playNote(57)
            try await Task.sleep(nanoseconds: 600_000_000)
            model.refreshPlaybackState()
            precondition(model.activeNote == nil)
            model.rootNote = 64
            model.setEnvelope(savedEnvelope)
            let modelDocument = root.appendingPathComponent("model.sfinstrument")
            await model.saveInstrument(sample: model.instrumentSample!, root: model.rootNote, to: modelDocument, remember: false)
            precondition(!model.instrumentDirty && model.instrumentFileURL == modelDocument)
            model.rootNote = 65
            precondition(model.instrumentDirty)
            let reopened = PlayerModel()
            defer { reopened.cleanup() }
            let opened = await reopened.loadInstrument(modelDocument, remember: false)
            precondition(opened && reopened.rootNote == 64 && !reopened.instrumentDirty && reopened.envelope == savedEnvelope)
            precondition(abs(reopened.instrumentSample!.duration - 0.2) < 0.00001)
            reopened.playNote(64)
            precondition(reopened.activeNote == 64)
            reopened.releaseNote()
            reopened.setEnvelope(.standard)
            precondition(reopened.instrumentDirty)
            let rejected = await reopened.loadInstrument(invalidDocument, remember: false)
            precondition(!rejected && reopened.rootNote == 64 && reopened.instrumentSample != nil)
            print("PASS: fresh model restoration, unchanged root/audio, dirty tracking, keyboard playback, failed-open preservation")
            print("PASS: instrument preparation, note on/off, replacement voice, stale note-off, gain metering, root change and natural end")

            // Render the production voice graph offline to verify audible pitch,
            // rather than testing only the semitone formula.
            for (note, frequency) in [(60, 440.0), (72, 880.0), (48, 220.0)] {
                let engine = AVAudioEngine()
                let sampler = SampleInstrument(engine: engine)
                let sample = try InstrumentSample.load(url: mono)
                sampler.install(sample)
                try engine.enableManualRenderingMode(.offline, format: sample.buffer.format, maximumFrameCount: 1024)
                try sampler.play(note: note, root: 60)
                let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
                var previous: Float = 0
                var crossings: [Int] = []
                var offset = 0
                for _ in 0..<32 {
                    let status = try engine.renderOffline(1024, to: buffer)
                    precondition(status == .success)
                    for i in 0..<Int(buffer.frameLength) {
                        let value = buffer.floatChannelData![0][i]
                        if offset + i > 2048 && offset + i < 16000 && previous <= 0 && value > 0 { crossings.append(offset + i) }
                        previous = value
                    }
                    offset += Int(buffer.frameLength)
                }
                precondition(crossings.count > 20)
                let measured = Double(crossings.count - 1) * 44100 / Double(crossings.last! - crossings.first!)
                precondition(abs(measured - frequency) < 3, "Unexpected pitch: \(measured)")
                sampler.shutdown()
                engine.disableManualRenderingMode()
            }
            for note in [48, 60, 72] {
                let engine = AVAudioEngine()
                let sampler = SampleInstrument(engine: engine)
                let sample = try InstrumentSample.load(url: mono)
                sampler.install(sample)
                try engine.enableManualRenderingMode(.offline, format: sample.buffer.format, maximumFrameCount: 512)
                try sampler.play(note: note, root: 60, envelope: ADSRParameters(attack: 0.04, decay: 0.04, sustain: 0.5, release: 0.1))
                let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
                var rendered: [Float] = []
                for block in 0..<40 {
                    if block == 16 { sampler.noteOff() }
                    let status = try engine.renderOffline(512, to: output)
                    precondition(status == .success)
                    rendered.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
                }
                func rms(_ range: Range<Int>) -> Double {
                    sqrt(rendered[range].reduce(0.0) { $0 + Double($1 * $1) } / Double(range.count))
                }
                let held = rms(5000..<7000)
                precondition(held > 0.001)
                precondition(rms(0..<441) < held)
                precondition(rms(8704..<9728) > held * 0.05, "Release must continue after note-off")
                precondition(rms(16000..<19000) < held * 0.001, "Release must end at all pitches")
                sampler.shutdown()
                engine.disableManualRenderingMode()
            }
            print("PASS: actual audio graph Attack, Sustain and Release tails at three pitches")
            print("PASS: production sampler offline render measured 440 / 880 / 220 Hz")
            print("PASS: load, play, pause, seek, stop, failed-load preservation, replace mono, gain, replay at end")
        }
    }
}
