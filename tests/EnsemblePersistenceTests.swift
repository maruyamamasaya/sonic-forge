import Foundation

enum EnsemblePersistenceTests {
    @MainActor static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-EnsembleSaveTests-" + UUID().uuidString)
        let suite = "SonicForge-EnsembleSaveTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let model = EnsembleModel(defaults: defaults)
        await model.addDemos(); await model.addDemos()
        model.parts[1].startBeat = 4.5; model.parts[3].startBeat = 256
        model.tempo = 137.5; model.masterDB = -8.5
        model.parts[0].name = "Warm Pad"; model.parts[0].gainDB = -4.5; model.parts[3].muted = true
        let sourceInstrument = directory.appendingPathComponent("source.sfinstrument")
        let sourcePerformance = directory.appendingPathComponent("source.sfperformance")
        let instrument = model.parts[0].instrument!
        try InstrumentDocument.save(sample: instrument.sample, rootNote: instrument.root,
                                    envelope: instrument.envelope, loop: instrument.loop, to: sourceInstrument)
        await model.loadInstrument(sourceInstrument, part: model.parts[0].id)
        try model.parts[0].performance.save(to: sourcePerformance)
        model.setPerformance(try PerformanceDocument.load(sourcePerformance), part: model.parts[0].id)
        let expected = try model.snapshot()
        let file = directory.appendingPathComponent("session.sfensemble")
        let saved = await model.save(to: file)
        precondition(saved && !model.dirty && model.fileURL == file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: sourceInstrument)
        try FileManager.default.removeItem(at: sourcePerformance)
        let restored = EnsembleModel(defaults: defaults)
        await restored.restoreLastSession()
        precondition(restored.parts.count == 4 && restored.fileURL == file && !restored.dirty && !restored.playing)
        precondition(restored.tempo == expected.tempo && restored.masterDB == expected.masterDB)
        for (original, part) in zip(expected.parts, restored.parts) {
            precondition(part.startBeat == original.startBeat)
            precondition(part.name == original.name && part.gainDB == original.gainDB && part.muted == original.muted)
            precondition(part.performance == original.performance && part.instrumentURL == nil)
            let actual = part.instrument!, before = original.instrument
            precondition(actual.name == before.name && actual.root == before.root && actual.envelope == before.envelope && actual.loop == before.loop)
            precondition(actual.sample.name == before.sample.name && actual.sample.buffer.format == before.sample.buffer.format)
            precondition(actual.sample.buffer.frameLength == before.sample.buffer.frameLength)
            let count = Int(actual.sample.buffer.frameLength)
            for channel in 0..<Int(actual.sample.buffer.format.channelCount) {
                for frame in 0..<count { precondition(actual.sample.buffer.floatChannelData![channel][frame] == before.sample.buffer.floatChannelData![channel][frame]) }
            }
        }
        // Every persistent control marks dirty; transient transport/meter state does not.
        let changes: [(EnsembleModel) -> Void] = [
            { $0.parts[0].name = "Renamed" }, { $0.parts[0].gainDB = -7 }, { $0.parts[0].muted.toggle() },
            { $0.parts[0].startBeat = 3.25 }, { $0.tempo = 99 }, { $0.masterDB = -11 },
            { $0.setPerformance(.preset(.arpeggio), part: $0.parts[0].id) }, { $0.remove($0.parts.last!.id) }
        ]
        for change in changes {
            let loaded = await restored.load(file, remember: false)
            precondition(loaded && !restored.dirty)
            change(restored); precondition(restored.dirty)
        }
        let loaded = await restored.load(file, remember: false); precondition(loaded)
        let ids = restored.parts.map(\.id)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        func invalidRead(_ object: [String: Any]) async throws {
            let bad = directory.appendingPathComponent("bad.sfensemble")
            try JSONSerialization.data(withJSONObject: object).write(to: bad)
            let accepted = await restored.load(bad)
            precondition(!accepted && restored.parts.map(\.id) == ids && restored.fileURL == file && !restored.dirty)
        }
        var legacy = object; legacy["version"] = 1
        var legacyParts = legacy["parts"] as! [[String: Any]]
        for index in legacyParts.indices { legacyParts[index].removeValue(forKey: "startBeat") }
        legacy["parts"] = legacyParts
        let legacyFile = directory.appendingPathComponent("legacy.sfensemble")
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyFile)
        let legacySnapshot = try EnsembleDocument.load(legacyFile)
        precondition(legacySnapshot.parts.allSatisfy { $0.startBeat == 0 })
        for badStart: Any in [-1.0, 257.0, "four", NSNull()] {
            var bad = object; var badParts = object["parts"] as! [[String: Any]]
            badParts[0]["startBeat"] = badStart; bad["parts"] = badParts
            try await invalidRead(bad)
        }
        var missingStart = object; var missingParts = object["parts"] as! [[String: Any]]
        missingParts[0].removeValue(forKey: "startBeat"); missingStart["parts"] = missingParts
        try await invalidRead(missingStart)
        var invalid = object; invalid["version"] = 99; try await invalidRead(invalid)
        invalid = object; invalid["tempo"] = 0; try await invalidRead(invalid)
        invalid = object; invalid["parts"] = []; try await invalidRead(invalid)
        var parts = object["parts"] as! [[String: Any]]
        parts[0]["gainDB"] = 2; invalid = object; invalid["parts"] = parts; try await invalidRead(invalid)
        parts = object["parts"] as! [[String: Any]]
        parts[0]["name"] = " "; invalid = object; invalid["parts"] = parts; try await invalidRead(invalid)
        // A corrupt later part must not partially replace an earlier successfully decoded part.
        parts = object["parts"] as! [[String: Any]]
        var brokenInstrument = parts[1]["instrument"] as! [String: Any]
        brokenInstrument["sampleWAV"] = Data("not audio".utf8).base64EncodedString()
        parts[1]["instrument"] = brokenInstrument
        invalid = object; invalid["parts"] = parts; try await invalidRead(invalid)
        parts = object["parts"] as! [[String: Any]]
        var performance = parts[0]["performance"] as! [String: Any]
        performance["notes"] = []; parts[0]["performance"] = performance
        invalid = object; invalid["parts"] = parts; try await invalidRead(invalid)
        let corrupt = directory.appendingPathComponent("corrupt.sfensemble")
        try Data("bad JSON".utf8).write(to: corrupt)
        let corruptAccepted = await restored.load(corrupt); precondition(!corruptAccepted && restored.parts.map(\.id) == ids)
        let oversized = directory.appendingPathComponent("huge.sfensemble")
        _ = FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(EnsembleDocument.maximumBytes + 1)); try handle.close()
        let oversizedAccepted = await restored.load(oversized); precondition(!oversizedAccepted)
        restored.masterDB = .nan
        let badSave = await restored.save(to: file)
        let after = try Data(contentsOf: file)
        precondition(!badSave && after == bytes && restored.dirty)
        // Startup still points to the successful file after failed save/read.
        let restart = EnsembleModel(defaults: defaults); await restart.restoreLastSession()
        precondition(restart.parts.count == 4 && restart.masterDB == -8.5)
        restart.tempo = 88; await restart.restoreLastSession(); precondition(restart.tempo == 88 && restart.dirty)
        try FileManager.default.removeItem(at: file)
        let missing = EnsembleModel(defaults: defaults); await missing.restoreLastSession()
        precondition(missing.parts.isEmpty && missing.error != nil && !missing.playing)
        print("PASS: self-contained four-part save/restart after source deletion, exact PCM/settings/performances/mix, dirty tracking, invalid/version/oversize/partial read and overwrite protection")
    }
    @MainActor static func integration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-EnsembleRestore-" + UUID().uuidString)
        let suite = "SonicForge-EnsembleRestore-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let model = EnsembleModel(defaults: defaults)
        await model.addDemos(); model.tempo = 240; model.masterDB = -6
        model.parts[0].gainDB = -3; model.parts[1].muted = true
        let file = directory.appendingPathComponent("duo.sfensemble")
        let saved = await model.save(to: file); precondition(saved)
        let restored = EnsembleModel(defaults: defaults); await restored.restoreLastSession()
        precondition(!restored.playing && !restored.dirty && restored.tempo == 240 && restored.parts[1].muted)
        restored.play()
        try await Task.sleep(nanoseconds: 180_000_000)
        precondition(restored.playing && restored.parts[0].voices >= 3 && restored.parts[0].level > -60)
        precondition(restored.parts[1].level <= -59 && !restored.dirty)
        restored.parts[1].muted = false
        // A pluck may be between notes at 120 ms; observe the next audible event.
        for _ in 0..<30 {
            if restored.parts[1].level > -60 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(restored.parts[1].level > -60 && restored.dirty)
        restored.stop()
        precondition(restored.parts.allSatisfy { $0.voices == 0 })
        restored.parts[1].startBeat = 2
        restored.play()
        try await Task.sleep(nanoseconds: 180_000_000)
        precondition(restored.parts[0].voices > 0 && restored.parts[1].voices == 0 && restored.heldNotes(part: restored.parts[1].id).isEmpty)
        precondition(restored.durationBeats > 17)
        restored.stop() // Cancel while the second part is still waiting.
        try await Task.sleep(nanoseconds: 550_000_000)
        precondition(!restored.playing && restored.parts.allSatisfy { $0.voices == 0 })
        restored.play()
        try await Task.sleep(nanoseconds: 650_000_000)
        precondition(restored.playing && restored.parts[1].voices > 0 && restored.parts[1].level > -60)
        restored.stop()
        print("PASS: delayed entry silence, tempo-based entry, extended duration, stop during wait and restart")
        print("PASS: restored ensemble real output, saved gain/mute/tempo, per-part unmute, transport stays clean and all-stop")
    }
}
