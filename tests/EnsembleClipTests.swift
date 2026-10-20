import Foundation
import AVFoundation

enum EnsembleClipTests {
    @MainActor static func run() async throws {
        let model = EnsembleModel(); await model.addDemos(); model.remove(model.parts[1].id)
        let part = model.parts[0], instrument = part.instrument!
        var intro = part.performance
        intro.notes = [PerformanceNote(beat: 0, duration: 0.5, pitch: 57, velocity: 100, channel: 0)]; intro.pedals = []
        model.setPerformance(intro, part: part.id)
        model.sections = [EnsembleSection(name: "Intro", beats: 2), EnsembleSection(name: "Verse", beats: 2), EnsembleSection(name: "Chorus", beats: 2)]
        part.sectionID = model.sections[0].id; model.tempo = 240
        model.addClip(part: part.id, sectionID: model.sections[2].id)
        let clipID = part.additionalClips[0].id
        var chorus = intro; chorus.name = "Chorus melody"; chorus.notes[0].pitch = 64
        model.setClipPerformance(chorus, part: part.id, clip: clipID)
        precondition(model.parts.count == 1 && part.additionalClips.count == 1 && part.instrument!.sample.buffer === instrument.sample.buffer)
        let events = try model.timeline()
        precondition(events.count == 4 && abs(events[2].time - 1) < 0.000001 && events[2].bytes[1] == 64)
        precondition(events[0].bytes[1] == 57 && part.performance == intro)
        let chorusSection = model.sections[2].id
        model.reorderSection(chorusSection, by: -1)
        let reordered = try model.timeline()
        precondition(abs(reordered[2].time - 0.5) < 0.000001)
        model.reorderSection(chorusSection, by: 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Clips-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("clips.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
        model.editClip(part: part.id, clip: clipID) { $0.repeatCount = 2 }
        precondition(model.dirty && part.repeatCount == 1)
        model.editClip(part: part.id, clip: clipID) { $0.repeatCount = 1 }
        model.movePart(part.id, to: 5, clip: UUID())
        precondition(part.startBeat == 0 && part.additionalClips[0].startBeat == 0)
        model.movePart(part.id, to: 0.25, clip: clipID)
        precondition(part.startBeat == 0 && part.additionalClips[0].startBeat == 0.25)
        let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false); precondition(loaded)
        precondition(restored.parts.count == 1 && restored.parts[0].additionalClips[0].id == clipID && restored.parts[0].additionalClips[0].performance == chorus)
        let bytes = try Data(contentsOf: file)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        precondition(object["version"] as! Int == 11)
        let ids = restored.parts.map(\.id)
        func reject(_ value: [String: Any]) async throws {
            let bad = dir.appendingPathComponent("bad.sfensemble")
            try JSONSerialization.data(withJSONObject: value).write(to: bad)
            let ok = await restored.load(bad, remember: false)
            precondition(!ok && restored.parts.map(\.id) == ids)
        }
        var bad = object; var parts = object["parts"] as! [[String: Any]]
        parts[0].removeValue(forKey: "additionalClips"); bad["parts"] = parts; try await reject(bad)
        parts = object["parts"] as! [[String: Any]]
        let clips = parts[0]["additionalClips"] as! [[String: Any]]
        parts[0]["additionalClips"] = clips + clips; bad = object; bad["parts"] = parts; try await reject(bad)
        parts = object["parts"] as! [[String: Any]]
        var invalid = clips; invalid[0]["sectionID"] = UUID().uuidString
        parts[0]["additionalClips"] = invalid; bad = object; bad["parts"] = parts; try await reject(bad)
        invalid = clips; invalid[0]["sectionID"] = model.sections[0].id.uuidString
        parts[0]["additionalClips"] = invalid; bad = object; bad["parts"] = parts; try await reject(bad)
        var legacy = object; legacy["version"] = 4
        parts = object["parts"] as! [[String: Any]]; parts[0].removeValue(forKey: "additionalClips"); legacy["parts"] = parts
        let oldFile = dir.appendingPathComponent("v4.sfensemble")
        try JSONSerialization.data(withJSONObject: legacy).write(to: oldFile)
        let old = try EnsembleDocument.load(oldFile)
        precondition(old.parts[0].additionalClips.isEmpty && old.sections.count == 3)
        restored.removeSection(chorusSection); precondition(restored.sections.count == 3 && restored.error != nil)
        let wav = dir.appendingPathComponent("clips.wav")
        try await EnsembleExport.write(try restored.snapshot(), to: wav)
        let buffer = try InstrumentSample.load(url: wav).buffer
        func energy(_ start: Double, _ end: Double) -> Double {
            (Int(start * 48000)..<Int(end * 48000)).reduce(0) { $0 + pow(Double(buffer.floatChannelData![0][$1]), 2) }
        }
        precondition(abs(Double(buffer.frameLength) / 48000 - 2.05) < 0.001)
        precondition(energy(0.05, 0.2) > 1e-8 && energy(1.05, 1.2) > 1e-8 && energy(0.8, 0.95) < 1e-12)
        if CommandLine.arguments.contains("--playback") { try await verifyLive(restored, clipID: clipID) }
        model.removeClip(part: part.id, clip: clipID)
        precondition(part.additionalClips.isEmpty && part.performance == intro)
        await restored.addSharedSongDemo() // Existing content is retained.
        precondition(restored.parts.count == 1 && restored.error != nil)
        let demo = EnsembleModel(); await demo.addSharedSongDemo()
        precondition(demo.parts.count == 2 && demo.parts[0].additionalClips.count == 1 && demo.parts[1].additionalClips.count == 1)
        _ = try demo.timeline()
        // Copy a repeated performance, then vary only the copy and render both sections.
        let copies = EnsembleModel(); await copies.addDemos(); copies.remove(copies.parts[1].id)
        let original = copies.parts[0]
        copies.setPerformance(intro, part: original.id)
        copies.sections = [EnsembleSection(name: "Source", beats: 4), EnsembleSection(name: "Variation", beats: 4), EnsembleSection(name: "Outro", beats: 4)]
        original.sectionID = copies.sections[0].id; original.startBeat = 0.25; original.repeatCount = 2; copies.tempo = 240
        let source = original.allClips[0]
        let duplicateID = copies.duplicateClip(part: original.id, clip: source.id, to: copies.sections[1].id)!
        precondition(original.allClips[0] == source && original.additionalClips[0].performance == source.performance)
        precondition(duplicateID != source.id && original.additionalClips[0].startBeat == 0.25 && original.additionalClips[0].repeatCount == 2)
        copies.editClip(part: original.id, clip: duplicateID) { $0.performance.transpose = 2; $0.performance.velocityPercent = 75 }
        precondition(original.performance == intro && original.allClips[0] == source)
        let extraID = copies.duplicateClip(part: original.id, clip: duplicateID, to: copies.sections[2].id)!
        precondition(extraID != duplicateID && original.additionalClips[1].performance.transpose == 2)
        let copyFile = dir.appendingPathComponent("copies.sfensemble")
        let copySaved = await copies.save(to: copyFile, remember: false); precondition(copySaved && !copies.dirty)
        let before = original.allClips
        precondition(copies.duplicateClip(part: original.id, clip: source.id, to: copies.sections[1].id) == nil)
        precondition(copies.duplicateClip(part: original.id, clip: source.id, to: UUID()) == nil)
        precondition(copies.duplicateClip(part: original.id, clip: UUID(), to: nil) == nil)
        precondition(original.allClips == before && !copies.dirty)
        let copyRestored = EnsembleModel(); let copyLoaded = await copyRestored.load(copyFile, remember: false)
        precondition(copyLoaded && copyRestored.parts[0].additionalClips == original.additionalClips)
        let copyEvents = try copyRestored.timeline()
        let ons = copyEvents.filter { $0.bytes[0] & 0xf0 == 0x90 && $0.bytes[2] > 0 }
        precondition(ons.count == 6 && ons[0].bytes[1] == 57 && ons[2].bytes[1] == 59 && ons[2].bytes[2] == 75)
        let copyWAV = dir.appendingPathComponent("copies.wav")
        try await EnsembleExport.write(try copyRestored.snapshot(), to: copyWAV)
        let copyBuffer = try InstrumentSample.load(url: copyWAV).buffer
        for start in [0.08, 1.08, 2.08] {
            let energy = (Int(start * 48000)..<Int((start + 0.06) * 48000)).reduce(0.0) { $0 + pow(Double(copyBuffer.floatChannelData![0][$1]), 2) }
            precondition(energy > 1e-8, "Every copied section must render audio")
        }
        precondition(copies.parts.count == 1 && original.instrument!.sample.buffer === copies.parts[0].instrument!.sample.buffer)
        copies.removeClip(part: original.id, clip: extraID)
        copies.sections[2].beats = 1
        let shortSaved = await copies.save(to: copyFile, remember: false); precondition(shortSaved)
        precondition(copies.duplicateClip(part: original.id, clip: source.id, to: copies.sections[2].id) == nil && !copies.dirty)
        copies.sections[2].beats = 4
        while copies.sections.count < 8 { copies.sections.append(EnsembleSection(name: "Extra", beats: 4)) }
        for section in copies.sections.dropFirst(2) {
            precondition(copies.duplicateClip(part: original.id, clip: source.id, to: section.id) != nil)
        }
        precondition(original.allClips.count == 8)
        precondition(copies.duplicateClip(part: original.id, clip: source.id, to: nil) == nil && original.allClips.count == 8)
        print("PASS: primary/additional clip duplication, independent variation, atomic rejection, v5 restoration and repeated copied-section WAV reload")
        print("PASS: shared instrument clips, independent performances/placement, v5 save/v4 migration, invalid/overlap preservation, same-row intro/chorus WAV and stop")
    }
    @MainActor private static func verifyLive(_ model: EnsembleModel, clipID: UUID) async throws {
        let part = model.parts[0]
        // Keep the exact 125 ms timeline/WAV assertions above. For live observation,
        // use 500 ms notes/gap so a delayed test wakeup is not mistaken for a missing note.
        model.editClipNotes(part: part.id, clip: part.primaryClipID) { $0[0].duration = 2 }
        model.editClipNotes(part: part.id, clip: clipID) { $0[0].duration = 2 }
        let events = try model.timeline()
        precondition(events.map(\.time) == [0, 0.5, 1, 1.5])
        let began = ProcessInfo.processInfo.systemUptime
        func observe(_ stage: String, timeout: Double = 2, condition: () -> Bool) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + timeout
            while true {
                if let error = model.error { throw AudioError.invalid("Clip playback \(stage): \(error)") }
                if condition() { return }
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    throw AudioError.invalid("Clip playback timeout (\(stage)): elapsed=\(ProcessInfo.processInfo.systemUptime - began), playing=\(model.playing), held=\(model.heldNotes(part: part.id)), voices=\(part.voices), level=\(model.level), beat=\(model.positionBeats)")
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        defer { model.stop() }
        model.play()
        try await observe("intro note 57 with audio") {
            model.playing && model.heldNotes(part: part.id) == [57] && part.voices > 0 && model.level > -60
        }
        try await observe("gap after intro") { model.playing && model.heldNotes(part: part.id).isEmpty }
        try await observe("additional clip note 64 with audio") {
            model.playing && model.heldNotes(part: part.id) == [64] && part.voices > 0 && model.level > -60
        }
        try await observe("natural completion", timeout: 4) {
            !model.playing && model.heldNotes(part: part.id).isEmpty && part.voices == 0 && model.level == -60
        }
        model.stop()
        model.play()
        try await observe("intro on replay") { model.playing && model.heldNotes(part: part.id) == [57] }
        model.stop()
        precondition(!model.playing && model.heldNotes(part: part.id).isEmpty && part.voices == 0)
        // The cancelled scheduler must not deliver the later clip after Stop.
        try await Task.sleep(nanoseconds: 1_600_000_000)
        precondition(!model.playing && model.heldNotes(part: part.id).isEmpty && part.voices == 0 && model.level == -60)
        print("PASS: live clip note/audio sequence, gap, natural completion, replay and cancellation without late notes")
    }

}
