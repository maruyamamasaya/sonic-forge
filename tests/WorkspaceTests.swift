import Foundation

enum WorkspaceTests {
    @MainActor static func run() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], other = model.parts[1]
        let primary = part.allClips[0], extra = part.additionalClips
        model.editClip(part: part.id, clip: part.primaryClipID) {
            $0.performance.transpose = 1; $0.performance.velocityPercent = 85; $0.startBeat = 0.25
        }
        precondition(part.performance.transpose == 1 && part.startBeat == 0.25 && part.additionalClips == extra)
        let edited = part.allClips
        model.editClip(part: part.id, clip: UUID()) { $0.performance.transpose = 9 }
        precondition(part.allClips == edited)
        let original = part.instrument!, otherInstrument = other.instrument!
        let adsr = ADSRParameters(attack: 0.12, decay: 0.2, sustain: 0.4, release: 0.7)
        model.setInstrumentSettings(part: part.id, root: 58, envelope: adsr, loop: original.loop)
        precondition(part.instrument!.root == 58 && part.instrument!.envelope == adsr && part.instrument!.sample.buffer === original.sample.buffer)
        precondition(other.instrument!.root == otherInstrument.root && other.instrument!.envelope == otherInstrument.envelope)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("workspace.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
        var badLoop = original.loop; badLoop.endFrame = 0
        model.setInstrumentSettings(part: part.id, root: 58, envelope: adsr, loop: badLoop)
        precondition(!model.dirty && part.instrument!.loop == original.loop && model.error != nil)
        let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
        precondition(loaded && restored.parts[0].performance == part.performance && restored.parts[0].startBeat == 0.25 && restored.parts[0].instrument!.root == 58 && restored.parts[0].instrument!.envelope == adsr)
        precondition(part.primaryClipID == primary.id)
        if CommandLine.arguments.contains("--playback") {
            restored.play(); try await Task.sleep(nanoseconds: 150_000_000)
            let before = restored.parts[0].performance
            restored.editClip(part: restored.parts[0].id, clip: restored.parts[0].primaryClipID) { $0.performance.transpose = 3 }
            restored.setInstrumentSettings(part: restored.parts[0].id, root: 60, envelope: adsr, loop: original.loop)
            precondition(restored.parts[0].performance == before && restored.parts[0].instrument!.root == 58)
            restored.stop(); precondition(restored.parts.allSatisfy { $0.voices == 0 })
        }
        // The visual note model must agree with production events at every repeat.
        var performance = PerformanceDocument.preset(.pedalStudy)
        performance.transpose = 2; performance.velocityPercent = 75
        let preview = try PerformanceNoteLayout.make(performance, repeatCount: 3, root: 60)
        let production = try EnsembleTimeline.events(performance, root: 60, tempo: 60, startBeat: 0, count: 3)
        let on = production.filter { $0.bytes[0] & 0xf0 == 0x90 }
        precondition(preview.notes.count == on.count && abs(preview.length - production.last!.time) < 1e-9)
        for (index, note) in preview.notes.enumerated() {
            // Presets are in event order; compare beat, pitch, strength to real MIDI.
            precondition(abs(note.beat - on[index].time) < 1e-9 && note.pitch == Int(on[index].bytes[1]) && note.velocity == Int(on[index].bytes[2]))
            precondition(note.duration > 0 && preview.pitchRange.contains(note.pitch))
        }
        let originalNotes = performance.notes
        precondition(preview.notes[0].duration == originalNotes[0].duration && preview.length > preview.notes.last!.beat + preview.notes.last!.duration)
        for count in [0, 17] {
            do { _ = try PerformanceNoteLayout.make(performance, repeatCount: count); preconditionFailure("Invalid repeat rendered") } catch { }
        }
        performance.notes[0].beat = Double.nan
        do { _ = try PerformanceNoteLayout.make(performance, repeatCount: 1); preconditionFailure("Invalid note rendered") } catch { }
        print("PASS: note preview matches repeated production MIDI pitch/velocity/time and pedal ending; rejects invalid values")
        print("PASS: selected primary clip editing, shared instrument settings, independent parts, invalid-loop preservation, v5 restoration and playback edit lock")
    }
}
