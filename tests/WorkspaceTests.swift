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
        try await noteEditing()
        try await noteHistory()
        try await multipleNotes()
        try await quantizeNotes()
        try await groupVelocity()
        try await groupLengths()
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
    @MainActor private static func noteEditing() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], id = part.primaryClipID
        let siblings = part.additionalClips, other = model.parts[1].allClips
        let original = part.performance
        precondition(model.editClipNotes(part: part.id, clip: id) {
            $0.append(PerformanceNote(beat: 0.25, duration: 0.5, pitch: 72, velocity: 73))
        })
        let index = part.performance.notes.count - 1
        precondition(model.editClipNotes(part: part.id, clip: id) {
            $0[index].pitch = 71; $0[index].beat = 0.5; $0[index].duration = 0.75; $0[index].velocity = 61
        })
        precondition(model.dirty && part.performance.pedals == original.pedals && part.additionalClips == siblings && model.parts[1].allClips == other)
        let changed = part.performance
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-NoteEditor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notes.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
        // Invalid edits never replace the document or mark a saved arrangement dirty.
        for mutation: (inout [PerformanceNote]) -> Void in [
            { $0[index].beat = Double.nan }, { $0[index].duration = 0 },
            { $0[index].pitch = 127 }, { $0[index].velocity = 0 },
            { $0[index].beat = 255; $0[index].duration = 2 },
            { $0.append($0[0]) }, { $0.removeAll() },
            { $0 = Array(repeating: $0[0], count: 257) }
        ] {
            precondition(!model.editClipNotes(part: part.id, clip: id, change: mutation))
            precondition(part.performance == changed && !model.dirty && model.error != nil)
        }
        let loaded = EnsembleModel(); let opened = await loaded.load(file, remember: false)
        precondition(opened && loaded.parts[0].performance == changed)
        let events = try EnsembleClips.events(part.allClips, root: part.instrument!.root, tempo: 60, sections: model.sections)
        precondition(events.contains { $0.time == 0.5 && $0.bytes == [0x90, 71, 61] })
        let wav = dir.appendingPathComponent("edited.wav")
        try await EnsembleExport.write(model.snapshot(), to: wav)
        let audio = try AudioAsset.load(wav)
        precondition(audio.duration > 0)
        precondition(model.editClipNotes(part: part.id, clip: id) { $0.remove(at: index) })
        precondition(part.performance == original)
        // Additional clip isolation and placement validation on a complete part.
        let extra = part.additionalClips[0]
        precondition(model.editClipNotes(part: part.id, clip: extra.id) { $0[0].velocity = 62 })
        precondition(part.performance == original && part.additionalClips[0].performance.notes[0].velocity == 62)
        let before = part.allClips
        precondition(!model.editClipNotes(part: part.id, clip: extra.id) { $0[0].duration = 30 })
        precondition(part.allClips == before)
        if CommandLine.arguments.contains("--playback") {
            model.play(); try await Task.sleep(nanoseconds: 100_000_000)
            precondition(!model.editClipNotes(part: part.id, clip: id) { $0[0].velocity = 1 })
            precondition(!model.canUndoNotes(part: part.id, clip: id) && !model.restoreNoteEdit(part: part.id, clip: id))
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: .move(1, 0)) == nil)
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0], action: .quantize(.quarter)) == nil)
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: .velocity(100)) == nil)
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: .duration(1)) == nil)
            precondition(part.performance == original); model.stop()
        }
        print("PASS: atomic note add/edit/delete, invalid edit preservation, sibling isolation, events, v5 restore, WAV reload and playback lock")
    }

    @MainActor private static func noteHistory() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], id = part.primaryClipID
        let original = part.performance, siblings = part.additionalClips
        var states = [original]
        let changes: [(inout [PerformanceNote]) -> Void] = [
            { $0.append(PerformanceNote(beat: 0.25, duration: 0.5, pitch: 72, velocity: 80)) },
            { $0[0].pitch += 1 }, { $0[0].beat += 0.25 },
            { $0[0].duration -= 0.25 }, { $0[0].velocity = 100 },
            { $0.removeLast() }
        ]
        for change in changes {
            precondition(model.editClipNotes(part: part.id, clip: id, change: change))
            states.append(part.performance)
        }
        for expected in states.dropLast().reversed() {
            precondition(model.restoreNoteEdit(part: part.id, clip: id))
            precondition(part.performance == expected && part.additionalClips == siblings)
        }
        precondition(!model.canUndoNotes(part: part.id, clip: id))
        // Failure and no-op must retain redo; a real branch clears it.
        precondition(!model.editClipNotes(part: part.id, clip: id) { $0[0].velocity = 0 })
        precondition(model.editClipNotes(part: part.id, clip: id) { _ in })
        for expected in states.dropFirst() {
            precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true))
            precondition(part.performance == expected)
        }
        precondition(!model.canRedoNotes(part: part.id, clip: id))
        precondition(model.restoreNoteEdit(part: part.id, clip: id))
        precondition(model.editClipNotes(part: part.id, clip: id) { $0[0].velocity = 101 })
        precondition(!model.canRedoNotes(part: part.id, clip: id))
        let extra = part.additionalClips[0]
        precondition(model.editClipNotes(part: part.id, clip: extra.id) { $0[0].velocity = 70 })
        let primary = part.performance
        precondition(model.restoreNoteEdit(part: part.id, clip: extra.id))
        precondition(part.performance == primary && part.additionalClips == siblings)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Undo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("undo.sfensemble")
        let saved = await model.save(to: url, remember: false); precondition(saved && !model.dirty)
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && model.dirty)
        precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true))
        let reopened = await model.load(url, remember: false)
        let loaded = model.parts[0]
        precondition(reopened && loaded.performance == primary && !model.canUndoNotes(part: loaded.id, clip: loaded.primaryClipID))
        for index in 0..<55 {
            precondition(model.editClipNotes(part: loaded.id, clip: loaded.primaryClipID) { $0[0].velocity = 50 + index % 2 })
        }
        var count = 0
        while model.restoreNoteEdit(part: loaded.id, clip: loaded.primaryClipID) { count += 1 }
        precondition(count == 50)
        model.setClipPerformance(original, part: loaded.id, clip: loaded.primaryClipID)
        precondition(!model.canRedoNotes(part: loaded.id, clip: loaded.primaryClipID))
        // An otherwise valid history entry cannot overflow a subsequently shortened section.
        model.sections[0].beats = 12
        precondition(model.editClipNotes(part: loaded.id, clip: loaded.primaryClipID) { $0.append(PerformanceNote(beat: 4, duration: 0.5, pitch: 72, velocity: 80)) })
        precondition(model.restoreNoteEdit(part: loaded.id, clip: loaded.primaryClipID))
        let before = loaded.performance
        model.sections[0].beats = 8
        precondition(!model.restoreNoteEdit(part: loaded.id, clip: loaded.primaryClipID, redo: true))
        precondition(loaded.performance == before && model.canRedoNotes(part: loaded.id, clip: loaded.primaryClipID))
        model.sections[0].beats = 12
        precondition(model.restoreNoteEdit(part: loaded.id, clip: loaded.primaryClipID, redo: true))
        print("PASS: note undo/redo for all edits, clip isolation, branching/no-op/failure, save/reload reset, 50-entry bound and placement rejection")
    }

    @MainActor private static func multipleNotes() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        model.sections[0].beats = 32; model.tempo = 240
        let part = model.parts[0], id = part.primaryClipID
        let original = part.performance, siblings = part.additionalClips
        let indices: Set<Int> = [0, 1]
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: indices, action: .move(0.25, 1)) == indices)
        for index in indices {
            var expected = original.notes[index]; expected.beat += 0.25; expected.pitch += 1
            precondition(part.performance.notes[index] == expected)
        }
        precondition(part.performance.notes[2] == original.notes[2] && part.additionalClips == siblings)
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == original)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: indices, action: .duplicate(4, 0)) == [3, 4])
        let copied = part.performance
        precondition(Array(copied.notes.prefix(3)) == original.notes)
        for (index, copy) in copied.notes.suffix(2).enumerated() {
            var expected = original.notes[index]; expected.beat += 4
            precondition(copy == expected)
        }
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == original)
        precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true) && part.performance == copied)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [3, 4], action: .delete) == [])
        precondition(part.performance == original)
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == copied)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Multi-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("multi.sfensemble")
        let saved = await model.save(to: url, remember: false); precondition(saved && !model.dirty)
        for action: EnsembleModel.NoteGroupAction in [.move(-100, 0), .move(0, 127), .duplicate(0, 0), .duplicate(100, 0), .move(.nan, 0)] {
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: indices, action: action) == nil)
            precondition(part.performance == copied && !model.dirty)
        }
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: Set(copied.notes.indices), action: .delete) == nil)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [999], action: .delete) == nil)
        precondition(part.performance == copied && part.additionalClips == siblings)
        let loaded = EnsembleModel(); let opened = await loaded.load(url, remember: false)
        precondition(opened && loaded.parts[0].performance == copied)
        let wav = dir.appendingPathComponent("multi.wav")
        try await EnsembleExport.write(model.snapshot(), to: wav)
        let audio = try AudioAsset.load(wav); precondition(audio.duration > 0)
        var maximum = original
        maximum.notes = (0..<256).map { PerformanceNote(beat: Double($0) * 0.25, duration: 0.2, pitch: 60, velocity: 80) }
        model.parts[0].repeatCount = 1; model.sections[0].beats = 128
        model.setClipPerformance(maximum, part: part.id, clip: id)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0], action: .duplicate(65, 0)) == nil)
        precondition(part.performance == maximum)
        print("PASS: atomic multi-note move/duplicate/delete, relative attributes, sibling preservation, one-step undo/redo, invalid bounds/overlap/count, save/restore and WAV")
    }

    @MainActor private static func quantizeNotes() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], id = part.primaryClipID
        part.repeatCount = 1
        var source = part.performance
        source.notes = [PerformanceNote(beat: 0.12, duration: 0.2, pitch: 57, velocity: 61, channel: 2),
                        PerformanceNote(beat: 0.64, duration: 0.2, pitch: 61, velocity: 83),
                        PerformanceNote(beat: 1.13, duration: 0.2, pitch: 64, velocity: 105)]
        let siblings = part.additionalClips
        for grid in NoteQuantizeGrid.allCases {
            model.setClipPerformance(source, part: part.id, clip: id)
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: .quantize(grid)) == [0, 2])
            let result = part.performance
            precondition(result.notes[1] == source.notes[1] && result.pedals == source.pedals && part.additionalClips == siblings)
            for index in [0, 2] {
                var expected = source.notes[index]; expected.beat = grid.snap(expected.beat)
                precondition(result.notes[index] == expected)
                precondition(abs(result.notes[index].beat / grid.beats - (result.notes[index].beat / grid.beats).rounded()) < 1e-8)
            }
            precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == source)
            precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true) && part.performance == result)
        }
        precondition(NoteQuantizeGrid.eighth.snap(0.25) == 0.5 && NoteQuantizeGrid.eighth.snap(0.75) == 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Quantize-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("quantize.sfensemble")
        let saved = await model.save(to: url, remember: false); precondition(saved && !model.dirty)
        let quantized = part.performance
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: .quantize(.sixteenthTriplet)) == [0, 2])
        precondition(!model.dirty && part.performance == quantized)
        let loaded = EnsembleModel(); let opened = await loaded.load(url, remember: false)
        precondition(opened && loaded.parts[0].performance == quantized)
        let events = try quantized.events(root: part.instrument!.root)
        precondition(events.contains { abs($0.time - quantized.notes[2].beat * 60 / quantized.tempo) < 1e-9 && $0.bytes[0] == 0x90 && $0.bytes[1] == 64 })
        var overlap = source
        overlap.notes = [PerformanceNote(beat: 0, duration: 0.4, pitch: 57, velocity: 60),
                         PerformanceNote(beat: 0.41, duration: 0.2, pitch: 57, velocity: 70)]
        model.setClipPerformance(overlap, part: part.id, clip: id)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [1], action: .quantize(.quarter)) == nil)
        precondition(part.performance == overlap && !model.canUndoNotes(part: part.id, clip: id))
        var boundary = source
        boundary.notes = [PerformanceNote(beat: 7.6, duration: 0.2, pitch: 57, velocity: 60)]
        model.setClipPerformance(boundary, part: part.id, clip: id)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0], action: .quantize(.quarter)) == nil)
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: .velocity(100)) == nil)
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: .duration(1)) == nil)
        precondition(part.performance == boundary)
        print("PASS: six quantize grids, ties/triplets, selected starts only, one-step undo/redo, no-op clean state, save/restore/events and atomic overlap/boundary rejection")
    }

    @MainActor private static func groupVelocity() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], id = part.primaryClipID
        let original = part.performance, siblings = part.additionalClips
        let other = model.parts[1].allClips
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: .velocity(90)) == [0, 2])
        for index in original.notes.indices {
            var expected = original.notes[index]; if index != 1 { expected.velocity = 90 }
            precondition(part.performance.notes[index] == expected)
        }
        let uniform = part.performance
        precondition(part.additionalClips == siblings && model.parts[1].allClips == other && part.performance.pedals == original.pedals)
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == original)
        precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true) && part.performance == uniform)
        var source = original
        source.notes[0].velocity = 1; source.notes[1].velocity = 64; source.notes[2].velocity = 127
        model.setClipPerformance(source, part: part.id, clip: id)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1, 2], action: .velocityOffset(20)) == [0, 1, 2])
        precondition(part.performance.notes.map(\.velocity) == [21, 84, 127])
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == source)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1, 2], action: .velocityOffset(-20)) == [0, 1, 2])
        precondition(part.performance.notes.map(\.velocity) == [1, 44, 107])
        let changed = part.performance
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Velocity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("velocity.sfensemble")
        let saved = await model.save(to: url, remember: false); precondition(saved && !model.dirty)
        for action: EnsembleModel.NoteGroupAction in [.velocity(0), .velocity(128), .velocity(Int.max), .velocityOffset(Int.min), .velocityOffset(127)] {
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: action) == nil)
            precondition(part.performance == changed && !model.dirty)
        }
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 1], action: .velocityOffset(0)) == [0, 1])
        precondition(!model.dirty)
        let loaded = EnsembleModel(); let opened = await loaded.load(url, remember: false)
        precondition(opened && loaded.parts[0].performance == changed)
        let events = try changed.events(root: part.instrument!.root)
        let noteOn = events.filter { $0.bytes[0] & 0xf0 == 0x90 }
        precondition(noteOn.map { Int($0.bytes[2]) } == changed.notes.map(\.velocity))
        let extra = part.additionalClips[0]
        precondition(model.editNoteGroup(part: part.id, clip: extra.id, indices: [0, 1], action: .velocity(77)) == [0, 1])
        precondition(part.performance == changed)
        precondition(model.restoreNoteEdit(part: part.id, clip: extra.id) && part.additionalClips == siblings)
        print("PASS: selected velocity set/offset, clipping bounds, attribute/sibling preservation, one-step history, invalid integer protection, no-op clean, save/restore and MIDI dynamics")
    }

    @MainActor private static func groupLengths() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], id = part.primaryClipID
        part.repeatCount = 1
        var source = part.performance
        source.notes[0].duration = 0.5; source.notes[1].duration = 1; source.notes[2].duration = 2
        model.setClipPerformance(source, part: part.id, clip: id)
        let siblings = part.additionalClips, other = model.parts[1].allClips
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: .duration(0.75)) == [0, 2])
        for index in source.notes.indices {
            var expected = source.notes[index]; if index != 1 { expected.duration = 0.75 }
            precondition(part.performance.notes[index] == expected)
        }
        let uniform = part.performance
        precondition(part.performance.pedals == source.pedals && part.additionalClips == siblings && model.parts[1].allClips == other)
        precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == source)
        precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true) && part.performance == uniform)
        precondition(model.restoreNoteEdit(part: part.id, clip: id))
        for factor in [0.5, 2.0] {
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: .durationScale(factor)) == [0, 2])
            precondition(part.performance.notes[0].duration == 0.5 * factor && part.performance.notes[2].duration == 2 * factor)
            precondition(part.performance.notes[2].duration / part.performance.notes[0].duration == 4)
            precondition(part.performance.notes[1] == source.notes[1])
            precondition(model.restoreNoteEdit(part: part.id, clip: id) && part.performance == source)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Lengths-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("lengths.sfensemble")
        let saved = await model.save(to: url, remember: false); precondition(saved && !model.dirty)
        for action: EnsembleModel.NoteGroupAction in [.duration(0), .duration(-1), .duration(.nan), .duration(.infinity), .duration(9),
            .durationScale(0), .durationScale(-1), .durationScale(.nan), .durationScale(.infinity), .durationScale(Double.greatestFiniteMagnitude)] {
            precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: action) == nil)
            precondition(part.performance == source && !model.dirty)
        }
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0, 2], action: .durationScale(1)) == [0, 2])
        precondition(!model.dirty && model.canRedoNotes(part: part.id, clip: id))
        precondition(model.restoreNoteEdit(part: part.id, clip: id, redo: true))
        let result = part.performance
        let savedAgain = await model.save(to: url, remember: false); precondition(savedAgain)
        let loaded = EnsembleModel(); let opened = await loaded.load(url, remember: false)
        precondition(opened && loaded.parts[0].performance == result)
        let events = try result.events(root: part.instrument!.root)
        for note in result.notes {
            precondition(events.contains { $0.bytes[0] & 0xf0 == 0x80 && Int($0.bytes[1]) == note.pitch && abs($0.time - (note.beat + note.duration) * 60 / result.tempo) < 1e-9 })
        }
        var collision = source
        collision.notes = [PerformanceNote(beat: 0, duration: 0.5, pitch: 57, velocity: 60), PerformanceNote(beat: 0.75, duration: 0.5, pitch: 57, velocity: 80)]
        model.setClipPerformance(collision, part: part.id, clip: id)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0], action: .duration(1)) == nil && part.performance == collision)
        precondition(model.editNoteGroup(part: part.id, clip: id, indices: [0], action: .durationScale(2)) == nil && part.performance == collision)
        print("PASS: selected duration set/proportional scale, fixed starts/attributes, subset isolation, one-step history, bounds/nonfinite/overlap rejection, no-op redo, save/restore and MIDI note-offs")
    }

}
