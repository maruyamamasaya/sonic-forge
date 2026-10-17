import Foundation
import AVFoundation

@main
struct AudioTests {
    @MainActor static func main() async throws {
        try PerformanceTests.run()
        try await EnsembleTests.run()
        try await EnsemblePersistenceTests.run()
        try await EnsembleExportTests.run()
        try await EnsembleSectionTests.run()
        try await SectionDuplicationTests.run()
        try await EnsembleClipTests.run()
        try await GenerationTests.run()
        if CommandLine.arguments.contains("--ai-live") { try await GenerationTests.live() }
        try await LibraryTests.run(playback: CommandLine.arguments.contains("--playback"))
        MIDITests.parser()
        EnvelopeTests.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForgeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = root.appendingPathComponent("demo.wav")
        try DemoAudio.write(to: demo)
        let demoSample = try InstrumentSample.load(url: demo)
        let pcm = demoSample.buffer.floatChannelData!
        let loopStart = 4800
        let loopEnd = (7200..<12000).max { abs(pcm[0][$0 - 1] - pcm[0][loopStart]) < abs(pcm[0][$1 - 1] - pcm[0][loopStart]) }!
        let voice = InstrumentVoice()
        voice.install(demoSample)
        let rendered = AVAudioPCMBuffer(pcmFormat: demoSample.buffer.format, frameCapacity: AVAudioFrameCount(loopEnd + 2))!
        rendered.frameLength = AVAudioFrameCount(loopEnd + 2)
        var boundarySteps: [Float] = []
        for fade: Int64 in [0, 480] {
            voice.trigger(.legacy, rate: 1, loop: SampleLoop(enabled: true, startFrame: Int64(loopStart), endFrame: Int64(loopEnd), crossfadeFrames: fade))
            voice.render(frames: rendered.frameLength, output: rendered.mutableAudioBufferList)
            boundarySteps.append(abs(rendered.floatChannelData![0][loopEnd] - rendered.floatChannelData![0][loopEnd - 1]))
        }
        precondition(boundarySteps[1] < boundarySteps[0] * 0.1)
        print("PASS: demo crossfade boundary step reduced by over 90 percent")
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
        let savedLoop = SampleLoop(enabled: true, startFrame: 100, endFrame: 200, crossfadeFrames: 20)
        let documentURL = root.appendingPathComponent("My Instrument.sfinstrument")
        try InstrumentDocument.save(sample: documentSample, rootNote: 64, envelope: savedEnvelope, loop: savedLoop, to: documentURL)
        try FileManager.default.removeItem(at: originalCopy)
        let restored = try InstrumentDocument.load(documentURL)
        defer { try? FileManager.default.removeItem(at: restored.directory) }
        precondition(restored.loop == savedLoop)
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
        precondition(!legacy.loop.enabled)
        var v2 = json
        v2["version"] = 2
        v2.removeValue(forKey: "loop")
        try JSONSerialization.data(withJSONObject: v2).write(to: legacyURL)
        let older = try InstrumentDocument.load(legacyURL)
        defer { try? FileManager.default.removeItem(at: older.directory) }
        precondition(!older.loop.enabled && older.envelope == savedEnvelope)
        for range in [[-1, 200], [200, 100], [0, 9999999], [100, 101]] {
            var invalid = json
            invalid["loop"] = ["enabled": true, "startFrame": range[0], "endFrame": range[1]]
            try JSONSerialization.data(withJSONObject: invalid).write(to: invalidDocument)
            do { _ = try InstrumentDocument.load(invalidDocument); fatalError("Invalid loop accepted") } catch {}
        }
        var v3 = json
        v3["version"] = 3
        var oldLoop = v3["loop"] as! [String: Any]
        oldLoop.removeValue(forKey: "crossfadeFrames")
        v3["loop"] = oldLoop
        try JSONSerialization.data(withJSONObject: v3).write(to: legacyURL)
        let oldLoopDocument = try InstrumentDocument.load(legacyURL)
        defer { try? FileManager.default.removeItem(at: oldLoopDocument.directory) }
        precondition(oldLoopDocument.loop.enabled && oldLoopDocument.loop.startFrame == 100 && oldLoopDocument.loop.crossfadeFrames == 0)
        for fade in [-1, 51, Int64.max] {
            var invalid = json
            invalid["loop"] = ["enabled": true, "startFrame": 100, "endFrame": 200, "crossfadeFrames": fade]
            try JSONSerialization.data(withJSONObject: invalid).write(to: invalidDocument)
            do { _ = try InstrumentDocument.load(invalidDocument); fatalError("Invalid crossfade accepted") } catch {}
        }
        print("PASS: v4 crossfade persistence and v3 OFF compatibility, invalid lengths rejected")
        print("PASS: v3 loop persistence, v1/v2 loop-off compatibility, invalid loop/envelope rejection")
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
            model.gainDB = -12
            await model.prepareInstrument(useSelection: false)
            precondition(model.instrumentSample != nil, model.error ?? "No sample; busy=\(model.busy)")
            model.playNote(60)
            precondition(model.activeNotes == [60])
            try await Task.sleep(nanoseconds: 150_000_000)
            model.refreshPlaybackState()
            precondition(model.levels[0] > -60)
            model.playNote(72)
            precondition(model.activeNotes == [60, 72])
            model.releaseNote(60)
            precondition(model.activeNotes == [72])
            model.releaseNote(72)
            precondition(model.activeNotes.isEmpty)
            model.playNote(60)
            model.rootNote = 57
            precondition(model.activeNotes.isEmpty)
            await model.load(demo, demo: true)
            model.select(from: 0, to: 0.025)
            await model.prepareInstrument()
            precondition(abs(model.instrumentSample!.duration - 0.2) < 0.00001)
            model.playNote(57)
            try await Task.sleep(nanoseconds: 600_000_000)
            model.refreshPlaybackState()
            precondition(model.activeNotes.isEmpty)
            model.rootNote = 64
            // A short demo loop must outlast its original 0.2-second sample.
            model.select(from: 0.005, to: 0.02)
            precondition(model.canSetLoopFromSelection)
            model.loopFromSelection()
            precondition(model.sampleLoop.enabled)
            model.playNote(64)
            try await Task.sleep(nanoseconds: 450_000_000)
            model.refreshPlaybackState()
            precondition(model.activeNotes == [64] && model.levels[0] > -60)
            model.releaseNote()
            model.stopInstrument()
            model.setEnvelope(savedEnvelope)
            model.setLoop(savedLoop)
            let modelDocument = root.appendingPathComponent("model.sfinstrument")
            await model.saveInstrument(sample: model.instrumentSample!, root: model.rootNote, to: modelDocument, remember: false)
            precondition(!model.instrumentDirty && model.instrumentFileURL == modelDocument)
            model.rootNote = 65
            precondition(model.instrumentDirty)
            let reopened = PlayerModel()
            defer { reopened.cleanup() }
            let opened = await reopened.loadInstrument(modelDocument, remember: false)
            precondition(opened && reopened.rootNote == 64 && !reopened.instrumentDirty && reopened.envelope == savedEnvelope && reopened.sampleLoop == savedLoop)
            precondition(abs(reopened.instrumentSample!.duration - 0.2) < 0.00001)
            reopened.playNote(64)
            precondition(reopened.activeNotes == [64])
            reopened.releaseNote()
            reopened.setEnvelope(.standard)
            precondition(reopened.instrumentDirty)
            let rejected = await reopened.loadInstrument(invalidDocument, remember: false)
            precondition(!rejected && reopened.rootNote == 64 && reopened.instrumentSample != nil)
            print("PASS: fresh model restoration, unchanged root/audio, dirty tracking, keyboard playback, failed-open preservation")
            print("PASS: instrument preparation, note on/off, independent note-off, gain metering, root change and natural end")

            // Computer and screen ownership must not release each other's key.
            reopened.stopInstrument()
            reopened.playNote(60, input: .computer)
            reopened.playNote(60, input: .screen)
            reopened.releaseNote(60, input: .screen)
            precondition(reopened.activeNotes == [60])
            reopened.releaseNote(60, input: .computer)
            precondition(reopened.activeNotes.isEmpty)
            reopened.holdKeys = true
            reopened.screenKeyDown(60); reopened.screenKeyUp(60)
            reopened.screenKeyDown(64); reopened.screenKeyUp(64)
            precondition(reopened.activeNotes == [60, 64])
            reopened.screenKeyDown(60); reopened.screenKeyUp(60)
            precondition(reopened.activeNotes == [64])
            reopened.stopInstrument()
            reopened.toggleDemoChord()
            precondition(reopened.activeNotes.count == 3)
            reopened.toggleDemoChord()
            precondition(reopened.activeNotes.isEmpty)
            print("PASS: input ownership, latched chord and demo chord release")

            do {
                let engine = AVAudioEngine()
                let sampler = SampleInstrument(engine: engine)
                let sample = try InstrumentSample.load(url: mono)
                sampler.install(sample)
                try engine.enableManualRenderingMode(.offline, format: sample.buffer.format, maximumFrameCount: 512)
                let parameters = ADSRParameters(attack: 0.01, decay: 0.02, sustain: 0.8, release: 0.1)
                let loop = SampleLoop(enabled: true, endFrame: Int64(sample.buffer.frameLength), crossfadeFrames: 441)
                for note in [60, 64, 67] { try sampler.play(note: note, root: 60, envelope: parameters, loop: loop) }
                precondition(sampler.heldNotes == [60, 64, 67] && sampler.soundingCount == 3)
                let buffer = AVAudioPCMBuffer(pcmFormat: sample.buffer.format, frameCapacity: 512)!
                var rendered: [Float] = []
                for block in 0..<140 {
                    if block == 40 { sampler.noteOff(64) }
                    let status = try engine.renderOffline(512, to: buffer)
                    precondition(status == .success)
                    rendered.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                }
                func amplitude(_ frequency: Double, _ range: Range<Int>) -> Double {
                    var real = 0.0, imaginary = 0.0
                    for i in range {
                        let phase = 2 * Double.pi * frequency * Double(i) / 44100
                        real += Double(rendered[i]) * cos(phase); imaginary += Double(rendered[i]) * sin(phase)
                    }
                    return 2 * hypot(real, imaginary) / Double(range.count)
                }
                let frequencies = [440.0, 440 * pow(2.0, 4.0 / 12), 440 * pow(2.0, 7.0 / 12)]
                for frequency in frequencies { precondition(amplitude(frequency, 8000..<16000) > 0.003) }
                precondition(amplitude(frequencies[1], 33000..<41000) < amplitude(frequencies[1], 8000..<16000) * 0.05)
                for frequency in [frequencies[0], frequencies[2]] { precondition(amplitude(frequency, 55000..<63000) > 0.001) }
                sampler.refreshCompletion()
                precondition(sampler.heldNotes == [60, 67] && sampler.soundingCount == 2)
                sampler.noteOff()
                for _ in 0..<30 { _ = try engine.renderOffline(512, to: buffer) }
                sampler.refreshCompletion()
                precondition(!sampler.isSounding && sampler.heldNotes.isEmpty)
                for note in 48...56 { try sampler.play(note: note, root: 60, loop: loop) }
                precondition(sampler.soundingCount == 8 && !sampler.heldNotes.contains(48))
                sampler.noteOff(52)
                try sampler.play(note: 60, root: 60, loop: loop)
                precondition(!sampler.heldNotes.contains(52) && sampler.heldNotes.contains(49))
                try sampler.play(note: 60, root: 60, loop: loop)
                precondition(sampler.soundingCount == 8)
                sampler.stop()
                precondition(!sampler.isSounding)
                sampler.shutdown(); engine.disableManualRenderingMode()
                print("PASS: actual polyphonic graph three pitches, independent Release, looping past EOF, eight-voice allocation and all-off")
            }

            try await MIDITests.integration()
            try await MIDITests.expression()
            try await PerformanceTests.integration()
            try await GenerationTests.integration()
            try await EnsembleTests.integration()
            try await EnsemblePersistenceTests.integration()

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
