import Foundation
import AVFoundation

enum RootRangeTests {
    @MainActor static func run() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("SonicForge-RootRange-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("Dsharp2.wav")
        let rate = 44100.0, frequency = 440 * pow(2, Double(39 - 69) / 12)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 35280)!
        pcm.frameLength = 35280
        for c in 0..<2 { for i in 0..<35280 { pcm.floatChannelData![c][i] = Float(0.3 * sin(2 * .pi * frequency * Double(i) / rate)) } }
        do { let file = try AVAudioFile(forWriting: wav, settings: format.settings); try file.write(from: pcm) }
        let sample = try InstrumentSample.load(url: wav)
        let loop = SampleLoop(endFrame: 35280)
        let envelope = ADSRParameters(attack: 0.005, decay: 0, sustain: 1, release: 0.1)
        let player = PlayerModel(materialStore: MaterialStore(root: dir.appendingPathComponent("unused-library")))
        for root in [24,39,48,57,60,72,96] {
            let url = dir.appendingPathComponent("root.sfinstrument")
            try InstrumentDocument.save(sample: sample, rootNote: root, envelope: envelope, loop: loop, to: url)
            let loaded = try EnsembleInstrument.load(url)
            precondition(loaded.root == root && loaded.envelope == envelope && loaded.loop == loop)
            let document = PerformanceDocument(name: "Root test", notes: [PerformanceNote(beat: 0, duration: 1, pitch: root, velocity: 100)], pedals: [])
            let song = EnsembleSnapshot(tempo: 120, masterDB: 0, parts: [EnsemblePartSnapshot(name: "Bass", instrument: loaded, performance: document, gainDB: 0, muted: false)])
            let file = dir.appendingPathComponent("song.sfensemble")
            try EnsembleDocument.save(song, to: file)
            let restoredSong = try EnsembleDocument.load(file)
            precondition(restoredSong.parts[0].instrument.root == root)
            player.rootNote = root
            precondition(player.rootNote == root && player.midi.performanceRoot == root)
            for preset in MIDIPerformancePreset.allCases {
                player.midi.performancePreset = preset
                _ = try player.midi.performance.events(root: root)
            }
            let keys = NotePitch.keyboardRange(root: root)
            precondition(keys.contains(root) && keys.count == 25)
            precondition(player.computerNote(0) == NotePitch.computerBase(root: root))
            precondition(player.computerNote(40) == NotePitch.computerBase(root: root) + 12)
            precondition(player.computerNote(999) == nil)
            for prompt in ["落ち着いた和音", "跳ねたフレーズ"] {
                _ = try PerformanceGeneration.demo(PerformanceBrief(prompt: prompt, root: root))
            }
        }
        let custom = player.midi.performance
        player.midi.performance = custom
        player.rootNote = 39
        precondition(player.midi.performance == custom) // Never transpose edited/imported notes implicitly.
        player.rootNote = 96
        precondition(NotePitch.keyboardRange(root: 39) == 24...48 && NotePitch.computerBase(root: 39) == 36)
        precondition(NotePitch.keyboardRange(root: 57) == 48...72 && NotePitch.computerBase(root: 57) == 60)
        for root in [23,97,-1,128] {
            do { _ = try InstrumentDocument.makeArchive(sample: sample, rootNote: root, envelope: envelope); fatalError("Invalid root accepted") } catch {}
            player.rootNote = root; precondition(player.rootNote == 96)
            do { try PerformanceBrief(prompt: "検証", root: root).validate(); fatalError("Invalid AI root accepted") } catch {}
        }
        let model = EnsembleModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let instrument = EnsembleInstrument(sample: sample, root: 48, envelope: envelope, loop: loop, name: "Bass")
        let perf = PerformanceDocument(name: "Low", notes: [PerformanceNote(beat: 0, duration: 1, pitch: 39, velocity: 100)], pedals: [])
        let part = model.addPart(instrument: instrument, performance: perf)!
        model.setInstrumentSettings(part: part.id, root: 39, envelope: envelope, loop: loop)
        precondition(part.instrument?.root == 39)
        precondition(model.restoreSongEdit() && part.instrument?.root == 48)
        precondition(model.restoreSongEdit(redo: true) && part.instrument?.root == 39)
        model.setInstrumentSettings(part: part.id, root: 23, envelope: envelope, loop: loop)
        precondition(part.instrument?.root == 39)
        let low = EnsembleInstrument(sample: sample, root: 39, envelope: envelope, loop: loop, name: "Dsharp2")
        for note in [27,39,51] {
            let performance = PerformanceDocument(name: "Pitch", notes: [PerformanceNote(beat: 0, duration: 1, pitch: note, velocity: 100)], pedals: [])
            let snapshot = EnsembleSnapshot(tempo: 120, masterDB: 0, parts: [EnsemblePartSnapshot(name: "Bass", instrument: low, performance: performance, gainDB: 0, muted: false)])
            let url = dir.appendingPathComponent("pitch.wav")
            try await EnsembleExport.write(snapshot, to: url)
            let buffer = try InstrumentSample.load(url: url).buffer
            let sr = buffer.format.sampleRate, x = buffer.floatChannelData![0]
            var crossings: [Double] = []
            for i in Int(sr * 0.03)..<Int(sr * 0.19) where x[i] <= 0 && x[i+1] > 0 {
                crossings.append(Double(i) + Double(-x[i] / (x[i+1] - x[i])))
            }
            precondition(crossings.count >= 5)
            let hz = Double(crossings.count-1) * sr / (crossings.last! - crossings.first!)
            let expected = frequency * Double(NotePitch.rate(note: note, root: 39))
            precondition(abs(hz - expected) < 0.5, "Low-note render must match assigned MIDI pitch")
        }
        if CommandLine.arguments.contains("--playback") {
            let file = dir.appendingPathComponent("low.sfinstrument")
            try InstrumentDocument.save(sample: sample, rootNote: 39, envelope: envelope, loop: loop, to: file)
            let loaded = await player.loadInstrument(file, remember: false); precondition(loaded && player.rootNote == 39)
            player.playNote(39); player.playNote(43); player.playNote(46)
            precondition(player.activeNotes == [39,43,46])
            player.rootNote = 40; precondition(player.activeNotes.isEmpty && player.instrumentDirty)
            player.stop()
        }
        print("PASS: C1-C7 root persistence, boundary rejection, keyboard register, low-root history/AI and absolute-pitch WAV render")
    }
}
