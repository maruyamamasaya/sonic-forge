import Foundation

enum PerformanceTests {
    @MainActor static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Performance-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for preset in MIDIPerformancePreset.allCases { _ = try PerformanceDocument.preset(preset).events(root: 60) }
        var document = PerformanceDocument.preset(.arpeggio)
        let original = try document.events()
        document.name = "My Arpeggio"; document.tempo = 60; document.transpose = 12; document.velocityPercent = 50
        let modified = try document.events()
        precondition(modified.first!.bytes == [0x90, 72, 25])
        for (before, after) in zip(original, modified) { precondition(abs(after.time - before.time * 2) < 0.000001) }
        let url = directory.appendingPathComponent("phrase.sfperformance")
        try document.save(to: url)
        let restored = try PerformanceDocument.load(url)
        precondition(restored == document)
        let bytes = try Data(contentsOf: url)
        let midi = MIDIInput()
        precondition(midi.loadPerformance(url) && midi.performance == document && !midi.performanceDirty)
        midi.performance.notes[0].velocity = 100
        precondition(midi.performanceDirty)
        precondition(midi.savePerformance(to: url) && !midi.performanceDirty)
        let second = MIDIInput()
        precondition(second.loadPerformance(url) && second.performance.notes[0].velocity == 100)
        let invalidURL = directory.appendingPathComponent("bad.sfperformance")
        func rejected(_ value: PerformanceDocument) throws {
            do { _ = try value.events(); fatalError("Invalid performance accepted") } catch {}
        }
        var invalid = document
        invalid.version = 99; try rejected(invalid)
        invalid = document; invalid.tempo = .nan; try rejected(invalid)
        invalid = document; invalid.tempo = 0; try rejected(invalid)
        invalid = document; invalid.notes[0].beat = .infinity; try rejected(invalid)
        invalid = document; invalid.notes[0].duration = 0; try rejected(invalid)
        invalid = document; invalid.notes[0].pitch = Int.max; try rejected(invalid)
        invalid = document; invalid.notes[0].channel = 16; try rejected(invalid)
        invalid = document; invalid.notes[0].velocity = 0; try rejected(invalid)
        invalid = document; invalid.transpose = 25; try rejected(invalid)
        invalid = document; invalid.velocityPercent = 200; try rejected(invalid)
        invalid = document; invalid.notes = []; try rejected(invalid)
        invalid = document; invalid.notes = Array(repeating: document.notes[0], count: 257); try rejected(invalid)
        invalid = document; invalid.notes.append(invalid.notes[0]); try rejected(invalid)
        invalid = document; invalid.pedals = [PerformancePedal(beat: 0, down: true)]; try rejected(invalid)
        invalid = document; invalid.notes = (60...68).map { PerformanceNote(beat: 0, duration: 1, pitch: $0, velocity: 80) }; try rejected(invalid)
        invalid.notes = (60...68).enumerated().map { PerformanceNote(beat: Double($0.offset), duration: 0.5, pitch: $0.element, velocity: 80) }
        invalid.pedals = [PerformancePedal(beat: 0, down: true), PerformancePedal(beat: 10, down: false)]
        try rejected(invalid)
        do { _ = try document.events(root: 48); fatalError("Unsupported sampler range accepted") } catch {}
        invalid = document; invalid.notes[0].duration = -1
        do { try invalid.save(to: url); fatalError("Invalid save accepted") } catch {}
        let preserved = try PerformanceDocument.load(url)
        precondition(preserved == second.performance)
        try Data("{}".utf8).write(to: invalidURL)
        precondition(!midi.loadPerformance(invalidURL) && midi.performance == second.performance)
        var unknown = document; unknown.version = 42
        try JSONEncoder().encode(unknown).write(to: invalidURL)
        do { _ = try PerformanceDocument.load(invalidURL); fatalError("Unknown version accepted") } catch {}
        // Adjacent same pitches are allowed; ending notes precede new ones.
        var adjacent = PerformanceDocument(name: "Adjacent", notes: [PerformanceNote(beat: 0, duration: 1, pitch: 60, velocity: 127), PerformanceNote(beat: 1, duration: 1, pitch: 60, velocity: 80)], pedals: [])
        let events = try adjacent.events()
        precondition(events[1].bytes[0] == 0x80 && events[2].bytes[0] == 0x90)
        adjacent.velocityPercent = 150
        let clamped = try adjacent.events()
        precondition(clamped.first!.bytes[2] == 127)
        precondition(!bytes.isEmpty)
        print("PASS: performance tempo/transpose/velocity, save/reopen/dirty, invalid data and overwrite protection, polyphony/pedal validation")
    }
    @MainActor static func integration() async throws {
        let model = PlayerModel()
        defer { model.cleanup() }
        await model.loadDemo()
        model.setLoop(SampleLoop(enabled: true, startFrame: 4800, endFrame: 9600, crossfadeFrames: 480))
        model.setEnvelope(ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.05))
        let midi = model.midi
        midi.performancePreset = .pedalStudy
        midi.performance.name = "Edited pedal phrase"
        midi.performance.tempo = 240; midi.performance.transpose = -5; midi.performance.velocityPercent = 50
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sfperformance")
        defer { try? FileManager.default.removeItem(at: url) }
        precondition(midi.savePerformance(to: url))
        let saved = midi.performance
        midi.resetPerformance()
        precondition(midi.loadPerformance(url) && midi.performance == saved && !midi.performanceDirty)
        midi.playPerformance()
        try await Task.sleep(nanoseconds: 700_000_000)
        model.refreshPlaybackState()
        precondition(model.activeNotes == [55, 59, 62] && model.sustainChannels == [0])
        try await Task.sleep(nanoseconds: 650_000_000)
        model.refreshPlaybackState()
        precondition(!midi.performing && model.activeNotes.isEmpty && model.sustainChannels.isEmpty && model.soundingVoices == 0)
        midi.performance.transpose = 24
        let selected = midi.selected
        midi.playPerformance()
        precondition(!midi.performing && midi.error != nil && midi.selected == selected)
        print("PASS: edited/saved/reloaded performance through CoreMIDI at changed tempo/pitch/dynamics, natural end and range rejection")
    }

}
