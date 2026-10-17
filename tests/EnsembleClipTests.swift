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
        precondition(object["version"] as! Int == 5)
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
        if CommandLine.arguments.contains("--playback") {
            restored.play(); try await Task.sleep(nanoseconds: 1_100_000_000)
            precondition(restored.playing && restored.heldNotes(part: restored.parts[0].id) == [64])
            restored.stop(); precondition(restored.parts[0].voices == 0)
        }
        model.removeClip(part: part.id, clip: clipID)
        precondition(part.additionalClips.isEmpty && part.performance == intro)
        await restored.addSharedSongDemo() // Existing content is retained.
        precondition(restored.parts.count == 1 && restored.error != nil)
        let demo = EnsembleModel(); await demo.addSharedSongDemo()
        precondition(demo.parts.count == 2 && demo.parts[0].additionalClips.count == 1 && demo.parts[1].additionalClips.count == 1)
        _ = try demo.timeline()
        print("PASS: shared instrument clips, independent performances/placement, v5 save/v4 migration, invalid/overlap preservation, same-row intro/chorus WAV and stop")
    }
}
