import Foundation
import AVFoundation

enum SectionDuplicationTests {
    @MainActor static func run() async throws {
        let model = EnsembleModel(); await model.addDemos()
        let first = model.parts[0], second = model.parts[1]
        var phrase = first.performance
        phrase.notes = [PerformanceNote(beat: 0, duration: 0.5, pitch: 57, velocity: 100, channel: 0)]
        phrase.pedals = []
        model.setPerformance(phrase, part: first.id); model.setPerformance(phrase, part: second.id)
        model.sections = [EnsembleSection(name: "Chorus", beats: 4), EnsembleSection(name: "Outro", beats: 4)]
        let sourceID = model.sections[0].id, outroID = model.sections[1].id
        first.sectionID = sourceID; first.startBeat = 0.25; first.repeatCount = 2
        second.sectionID = outroID
        model.addClip(part: second.id, sectionID: sourceID)
        let extraID = second.additionalClips[0].id
        model.editClip(part: second.id, clip: extraID) { $0.startBeat = 2; $0.performance.transpose = 3; $0.performance.velocityPercent = 80 }
        model.tempo = 240
        let originalFirst = first.allClips, originalSecond = second.allClips
        let pcm = first.instrument!.sample.buffer
        let copyID = model.duplicateSection(sourceID)!
        precondition(model.sections.map(\.id) == [sourceID, copyID, outroID] && model.sections[1].beats == 4)
        precondition(model.sections[1].name == "Chorus · Copy" && model.parts.count == 2 && first.instrument!.sample.buffer === pcm)
        precondition(first.allClips.dropLast() == originalFirst[...])
        precondition(second.allClips.dropLast() == originalSecond[...])
        let a = first.additionalClips[0], b = second.additionalClips[1]
        precondition(a.id != originalFirst[0].id && a.sectionID == copyID && a.startBeat == 0.25 && a.repeatCount == 2 && a.performance == phrase)
        precondition(b.id != extraID && b.startBeat == 2 && b.performance == originalSecond[1].performance)
        model.editClip(part: first.id, clip: a.id) { $0.performance.transpose = 2; $0.performance.velocityPercent = 75 }
        precondition(first.performance == phrase && model.sectionOffset(for: second) == 8)
        let events = try model.timeline()
        let copiedOn = events.first { $0.part == first.id && $0.time > 1 && $0.bytes[0] & 0xf0 == 0x90 }!
        precondition(abs(copiedOn.time - 1.0625) < 1e-6 && copiedOn.bytes[1] == 59 && copiedOn.bytes[2] == 75)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-SectionCopy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("copy.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
        let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
        precondition(loaded && restored.sections == model.sections && restored.parts[0].additionalClips == first.additionalClips && restored.parts[1].additionalClips == second.additionalClips)
        let wav = dir.appendingPathComponent("copy.wav")
        try await EnsembleExport.write(try restored.snapshot(), to: wav)
        let buffer = try InstrumentSample.load(url: wav).buffer
        for time in [0.08, 1.08, 1.52, 2.02] {
            let energy = (Int(time * 48000)..<Int((time + 0.05) * 48000)).reduce(0.0) { $0 + pow(Double(buffer.floatChannelData![0][$1]), 2) }
            precondition(energy > 1e-8, "Source, copied parts and shifted outro must render")
        }
        if CommandLine.arguments.contains("--playback") {
            restored.play(); try await Task.sleep(nanoseconds: 1_100_000_000)
            precondition(restored.playing && restored.heldNotes(part: restored.parts[0].id) == [59])
            let count = restored.sections.count
            precondition(restored.duplicateSection(copyID) == nil && restored.sections.count == count)
            restored.stop(); precondition(restored.parts.allSatisfy { $0.voices == 0 })
        }
        precondition(model.duplicateSection(UUID()) == nil && !model.dirty)
        // Song placements stay absolute; reject a newly introduced overlap atomically.
        second.sectionID = nil; second.startBeat = 12
        let songSaved = await model.save(to: file, remember: false); precondition(songSaved)
        let beforeSections = model.sections, beforeClips = model.parts.map(\.allClips)
        // Duplicating the original pushes the later copy into Song's fixed placement.
        second.startBeat = 10
        let fixedSaved = await model.save(to: file, remember: false); precondition(fixedSaved)
        precondition(model.duplicateSection(sourceID) == nil && !model.dirty)
        precondition(model.sections == beforeSections && first.allClips == beforeClips[0] && second.additionalClips == Array(beforeClips[1].dropFirst()))
        second.sectionID = outroID; second.startBeat = 0
        // A full later part must not leave earlier parts or a new section behind.
        model.sections = [EnsembleSection(id: sourceID, name: "Chorus", beats: 16), EnsembleSection(id: copyID, name: "Copy", beats: 16), EnsembleSection(id: outroID, name: "Outro", beats: 16)]
        for start in [4.0, 6, 8, 10, 12] {
            model.addClip(part: second.id, sectionID: sourceID)
            let id = second.additionalClips.last!.id
            model.editClip(part: second.id, clip: id) { $0.startBeat = start }
        }
        precondition(second.allClips.count == 8)
        let fullSaved = await model.save(to: file, remember: false); precondition(fullSaved)
        let counts = model.parts.map { $0.allClips.count }
        precondition(model.duplicateSection(sourceID) == nil && !model.dirty && model.parts.map { $0.allClips.count } == counts && model.sections.count == 3)
        let empty = EnsembleModel(); empty.sections = [EnsembleSection(name: String(repeating: "長", count: 40), beats: 1)]
        precondition(empty.duplicateSection(empty.sections[0].id) != nil && empty.sections[1].name.count <= 40)
        while empty.sections.count < 8 { precondition(empty.duplicateSection(empty.sections.last!.id) != nil) }
        precondition(empty.duplicateSection(empty.sections[0].id) == nil && empty.sections.count == 8)
        print("PASS: atomic whole-section duplication of primary/additional clips, independent variation, downstream placement, capacity/overlap rejection, v5 restore, WAV reload and stop")
    }
}
