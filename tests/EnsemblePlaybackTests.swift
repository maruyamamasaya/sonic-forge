import Foundation

@MainActor
enum EnsemblePlaybackTests {
    static func run() async throws {
        let a = UUID(), b = UUID()
        let events: [EnsembleModel.Event] = [
            .init(time: 0, part: a, bytes: [0xB2, 64, 127, 0x92, 57, 65]),
            .init(time: 0.5, part: a, bytes: [0x82, 57, 0]),
            .init(time: 0.75, part: b, bytes: [0x90, 60, 90]),
            .init(time: 1, part: b, bytes: [0x80, 60, 0, 0x90, 64, 100]),
            .init(time: 1.5, part: a, bytes: [0xB2, 64, 0]),
            .init(time: 2, part: b, bytes: [0x80, 64, 0, 0x90, 67, 80])
        ]
        let plan = try EnsemblePlayback.plan(events: events, start: 1, end: 2, tempo: 60)
        precondition(plan.initial.count == 2 && plan.events.count == 2)
        precondition(plan.initial[0].part == a && plan.initial[0].bytes == [0xB2, 64, 127, 0x92, 57, 65, 0x82, 57, 0])
        precondition(plan.initial[1].part == b && plan.initial[1].bytes == [0x90, 60, 90])
        precondition(plan.events[0].time == 0 && plan.events[1].time == 0.5)
        precondition(!plan.events.contains { $0.bytes.contains(67) }) // end is exclusive
        let cleared = try EnsemblePlayback.plan(events: events, start: 1.75, end: 2, tempo: 60)
        precondition(cleared.initial.count == 1 && cleared.initial[0].part == b)
        let scaled = try EnsemblePlayback.plan(events: events, start: 2, end: 4, tempo: 120)
        precondition(scaled.initial.map(\.bytes) == plan.initial.map(\.bytes))
        for (start, end) in [(Double.nan, 2.0), (-1, 2), (2, 2), (3, 2), (0, Double.infinity)] {
            do { _ = try EnsemblePlayback.plan(events: events, start: start, end: end, tempo: 60); fatalError("Bad playback range accepted") } catch {}
        }
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let revision = model.arrangementRevision, undo = model.undoSongLabel, original = model.parts.map(\.allClips)
        model.loopSection(model.sections[2].id)
        precondition(model.playbackRange == 24..<40 && model.rangeLoopEnabled && model.positionBeats == 24)
        model.seek(to: 30); precondition(model.positionBeats == 30)
        model.seek(to: 3); precondition(model.positionBeats == 24)
        precondition(!model.setPlaybackRange(start: 4, end: 4) && model.playbackRange == 24..<40)
        precondition(!model.setPlaybackRange(start: 0, end: 41))
        model.setRangeLoopEnabled(false); model.seek(to: 5)
        precondition(model.positionBeats == 5 && !model.rangeLoopEnabled)
        model.seek(to: .nan); model.seek(to: -1)
        precondition(model.positionBeats == 5 && model.arrangementRevision == revision && model.undoSongLabel == undo)
        precondition(model.parts.map(\.allClips) == original)
        model.stop(); precondition(model.positionBeats == 0 && !model.playing)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("audition.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved)
        model.setRangeLoopEnabled(true); model.seek(to: 28)
        precondition(!model.dirty && model.arrangementRevision == revision)
        let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
        precondition(loaded && restored.playbackRange == nil && !restored.rangeLoopEnabled && restored.positionBeats == 0)
        // Audition range has no effect on full-song export or arrangement events.
        let beforeEvents = try model.timeline(), afterEvents = try restored.timeline()
        precondition(beforeEvents.count == afterEvents.count)
        let wav = dir.appendingPathComponent("whole-song.wav")
        try await EnsembleExport.write(model.snapshot(), to: wav)
        let audio = try AudioAsset.load(wav)
        precondition(audio.duration >= 40 * 60 / model.tempo)
        if CommandLine.arguments.contains("--playback") { try await live() }
        print("PASS: audition seek/range validation, held-note/pedal chase, exclusive boundaries, tempo, session-only state and unchanged full-song WAV")
    }
    private static func live() async throws {
        let model = EnsembleModel(); await model.addDemos()
        model.remove(model.parts[1].id)
        let part = model.parts[0]
        model.setPerformance(PerformanceDocument(name: "Held", notes: [.init(beat: 0, duration: 4, pitch: 57, velocity: 80)], pedals: [.init(beat: 0, down: true), .init(beat: 4, down: false)]), part: part.id)
        model.tempo = 240
        model.seek(to: 2); model.play()
        try await Task.sleep(nanoseconds: 70_000_000)
        precondition(model.playing && model.positionBeats >= 2 && model.heldNotes(part: part.id) == [57])
        precondition(model.pedalChannels(part: part.id) == [0])
        model.pause(); let paused = model.positionBeats
        precondition(!model.playing && paused >= 2 && model.heldNotes(part: part.id).isEmpty)
        model.play(); try await Task.sleep(nanoseconds: 50_000_000)
        precondition(model.playing && model.positionBeats >= paused)
        model.pause()
        precondition(model.setPlaybackRange(start: 1, end: 2))
        model.play()
        for _ in 0..<20 {
            if model.playbackPass >= 3 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(model.playing && model.playbackPass >= 3 && (1...2).contains(model.positionBeats))
        precondition(model.heldNotes(part: part.id) == [57] && model.pedalChannels(part: part.id) == [0])
        model.seek(to: 1.5); try await Task.sleep(nanoseconds: 30_000_000)
        precondition(model.playing && model.heldNotes(part: part.id) == [57])
        model.pause(); precondition(model.rangeLoopEnabled && model.playbackRange == 1..<2)
        model.editClipNotes(part: part.id, clip: part.primaryClipID) { $0[0].velocity = 45 }
        model.play(); try await Task.sleep(nanoseconds: 30_000_000)
        precondition(model.playing && part.performance.notes[0].velocity == 45)
        model.stop(); let passes = model.playbackPass
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(!model.playing && model.positionBeats == 0 && model.playbackPass == passes)
        precondition(model.heldNotes(part: part.id).isEmpty && model.pedalChannels(part: part.id).isEmpty && part.voices == 0)
        let host = PlayerModel()
        await host.ensemble.addDemos()
        host.ensemble.seek(to: 2)
        host.prepareEnsemblePlayback()
        precondition(host.ensemble.positionBeats == 2 && !host.ensemble.playing)
        host.cleanup()
        print("PASS: live mid-song chase, pause/resume, repeated range wrapping, seek while playing, stop/edit/replay and cancellation without stuck notes")
    }
}
