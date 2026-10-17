import Foundation
import AVFoundation

enum EnsembleSectionTests {
    @MainActor static func run() async throws {
        let model = EnsembleModel()
        await model.addSongDemo()
        precondition(model.error == nil && model.parts.count == 3 && model.sections.count == 3)
        model.tempo = 120
        let timeline = try model.timeline()
        let verse = model.parts[1], chorus = model.parts[2]
        precondition(abs(timeline.first { $0.part == verse.id }!.time - 4) < 0.000001)
        precondition(abs(timeline.first { $0.part == chorus.id }!.time - 12) < 0.000001)
        let original = verse.performance
        let introID = model.sections[0].id
        model.reorderSection(introID, by: 1)
        precondition(model.sectionOffset(for: verse) == 0 && model.sectionOffset(for: model.parts[0]) == 16)
        precondition(verse.performance == original)
        model.sections[0].beats = 20
        precondition(model.sectionOffset(for: chorus) == 28)
        model.removeSection(introID)
        precondition(model.sections.count == 3 && model.error != nil)
        let spare = EnsembleSection(name: "Outro", beats: 4)
        model.sections.append(spare); model.removeSection(spare.id)
        precondition(model.sections.count == 3)
        model.movePart(verse.id, to: 256)
        precondition(abs(verse.startBeat - (20 - 15.87)) < 0.000001)
        verse.startBeat = 0
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Sections-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("song.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
        model.sections[0].name = "Renamed"; precondition(model.dirty)
        let loaded = await model.load(file, remember: false); precondition(loaded && !model.dirty)
        precondition(model.sections[0].name == "Aメロ" && model.sections[1].id == introID)
        precondition(model.parts[1].sectionID == model.sections[0].id && model.parts[0].repeatCount == 2)
        let bytes = try Data(contentsOf: file)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let ids = model.parts.map(\.id)
        func reject(_ value: [String: Any]) async throws {
            let bad = dir.appendingPathComponent("bad.sfensemble")
            try JSONSerialization.data(withJSONObject: value).write(to: bad)
            let ok = await model.load(bad, remember: false)
            precondition(!ok && model.parts.map(\.id) == ids && model.sections[1].id == introID)
        }
        var bad = object; bad.removeValue(forKey: "sections"); try await reject(bad)
        var sections = object["sections"] as! [[String: Any]]
        sections[1]["id"] = sections[0]["id"]; bad = object; bad["sections"] = sections; try await reject(bad)
        sections = object["sections"] as! [[String: Any]]
        sections[0]["beats"] = 0; bad = object; bad["sections"] = sections; try await reject(bad)
        var parts = object["parts"] as! [[String: Any]]
        parts[1]["sectionID"] = UUID().uuidString; bad = object; bad["parts"] = parts; try await reject(bad)
        parts = object["parts"] as! [[String: Any]]
        parts[1]["repeatCount"] = 16; bad = object; bad["parts"] = parts; try await reject(bad)
        var legacy = object; legacy["version"] = 3; legacy.removeValue(forKey: "sections")
        parts = object["parts"] as! [[String: Any]]
        for i in parts.indices { parts[i].removeValue(forKey: "sectionID") }
        legacy["parts"] = parts
        let oldFile = dir.appendingPathComponent("old.sfensemble")
        try JSONSerialization.data(withJSONObject: legacy).write(to: oldFile)
        let old = try EnsembleDocument.load(oldFile)
        precondition(old.sections.isEmpty && old.parts.allSatisfy { $0.sectionID == nil } && old.parts[0].repeatCount == 2)
        model.sections[0].beats = 1
        let accepted = await model.save(to: file, remember: false)
        let after = try Data(contentsOf: file)
        precondition(!accepted && after == bytes)

        // An assigned part enters after a silent section; the final empty section remains in the WAV.
        let render = EnsembleModel(); await render.addDemos(); render.remove(render.parts[1].id)
        var phrase = render.parts[0].performance
        phrase.notes = [PerformanceNote(beat: 0, duration: 0.25, pitch: 57, velocity: 100, channel: 0)]; phrase.pedals = []
        render.setPerformance(phrase, part: render.parts[0].id)
        render.sections = [EnsembleSection(name: "Silence", beats: 2), EnsembleSection(name: "Entry", beats: 2), EnsembleSection(name: "End", beats: 4)]
        render.parts[0].sectionID = render.sections[1].id; render.tempo = 240
        let wav = dir.appendingPathComponent("sections.wav")
        try await EnsembleExport.write(try render.snapshot(), to: wav)
        let audio = try InstrumentSample.load(url: wav).buffer
        func energy(_ a: Int, _ b: Int) -> Double { (a..<b).reduce(0) { $0 + pow(Double(audio.floatChannelData![0][$1]), 2) } }
        precondition(abs(Double(audio.frameLength) / 48000 - 2.55) < 0.001)
        precondition(energy(0, 23000) < 1e-12 && energy(26000, 35000) > 1e-8)
        precondition(energy(80000, 90000) < 1e-12)
        if CommandLine.arguments.contains("--playback") {
            render.play()
            try await Task.sleep(nanoseconds: 1_400_000_000)
            precondition(render.playing && render.durationBeats == 8)
            render.stop(); precondition(!render.playing && render.parts[0].voices == 0)
        }
        print("PASS: song sections order/length/assignment, fit validation, v4 save/legacy load/failure preservation, silent intro/end WAV and playback duration")
    }
}
