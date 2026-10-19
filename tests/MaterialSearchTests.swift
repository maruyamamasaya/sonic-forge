import Foundation
import AVFoundation
import SQLite3

// Temporary catalogs only. No test opens the user's material directory.
enum MaterialSearchTests {
    @MainActor static func run() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SonicForge-MaterialSearch-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func execute(_ file: URL, _ sql: String, _ args: [String] = []) throws -> [[String]] {
            var db: OpaquePointer?; precondition(sqlite3_open(file.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?; precondition(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            for (i, arg) in args.enumerated() { _ = arg.withCString { sqlite3_bind_text(statement, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } }
            var rows: [[String]] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return rows }
                precondition(status == SQLITE_ROW)
                rows.append((0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_text(statement, $0)) })
            }
        }
        func audio(_ name: String, gain: Float) throws -> URL {
            let url = root.appendingPathComponent(name)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132300)!
            buffer.frameLength = 132300
            for c in 0..<2 { for f in 0..<132300 { buffer.floatChannelData![c][f] = gain * Float(sin(Double(f) / 44100 * .pi * 880 + Double(c))) } }
            try file.write(from: buffer)
            return url
        }
        let original = try audio("input.wav", gain: 0.15), stem = try audio("drums.wav", gain: 0.3)
        let p = MaterialProvenance(sourceName: "比較の曲 ＡＢＣ", inputSHA256: try MaterialHash.file(original), runID: UUID().uuidString,
            model: "htdemucs", backend: "mlx-metal", settings: .standard, weightSHA256: SeparationClient.weightHash,
            versions: ["fixture":"1"], gain: 1, preprocessing: "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1", stem: "drums", frames: 132300, sampleRate: 44100)
        let origin = MaterialOrigin(provenance: p, input: original, original: original, stem: stem, lease: nil)
        let libraryRoot = root.appendingPathComponent("library"), database = libraryRoot.appendingPathComponent("catalog.sqlite")
        let initial = MaterialStore(root: libraryRoot)
        let draft = try await initial.prepare(origin: origin, selection: AudioSelection(startFrame: 22050, endFrame: 110250), name: "硬いＫＩＣＫ")
        let first = try await initial.commit(draft.id)
        let secondDraft = try await initial.prepare(origin: origin, selection: AudioSelection(startFrame: 22051, endFrame: 110250), name: "別の素材")
        let second = try await initial.commit(secondDraft.id)
        // Convert the fixture to the previously shipped v1 schema, preserving its records/blobs.
        for sql in ["DROP TABLE material_reclaims", "DROP TABLE material_retentions", "DROP TABLE material_tombstones", "DROP TABLE material_trash", "DROP TABLE material_tags", "DROP TABLE tags", "DROP TABLE material_annotations", "PRAGMA user_version=1"] { _ = try execute(database, sql) }
        let brokenRoot = root.appendingPathComponent("broken-migration")
        try fm.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
        let broken = brokenRoot.appendingPathComponent("catalog.sqlite")
        try fm.copyItem(at: database, to: broken)
        _ = try execute(broken, "UPDATE materials SET payload=? WHERE id=?", ["invalid json", first.id])
        do { _ = try await MaterialStore(root: brokenRoot).search(); fatalError("Invalid migration succeeded") } catch {}
        let failedVersion = try execute(broken, "PRAGMA user_version")
        let failedTables = try execute(broken, "SELECT name FROM sqlite_master WHERE name='material_annotations'")
        precondition(failedVersion[0][0] == "1" && failedTables.isEmpty)
        let retained = try execute(broken, "SELECT payload FROM materials WHERE id=?", [first.id])
        precondition(retained[0][0] == "invalid json")
        let store = MaterialStore(root: libraryRoot)
        let migrated = try await store.search()
        precondition(migrated.total == 2 && migrated.items.allSatisfy { $0.annotations == .empty })
        let backups = try fm.contentsOfDirectory(at: libraryRoot.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        precondition(backups.count == 1)
        let backupVersion = try execute(backups[0], "PRAGMA user_version"), backupCount = try execute(backups[0], "SELECT count(*) FROM materials")
        precondition(backupVersion[0][0] == "1" && backupCount[0][0] == "2")
        let saved = try await store.updateAnnotations(first.id, tags: [" ドラム ", "ＫＩＣＫ", "kick", "100%", "a_b", "C\\D"], note: "明るい音。Ｏ’Ｂｒｉｅｎ 雨の日")
        precondition(saved.tags.count == 5 && saved.note.contains("Ｏ’Ｂｒｉｅｎ"))
        for query in ["硬い", "kick", "比較の曲 abc", "ドラム", "雨の日", "100%", "a_b", "c\\d", "ｋｉｃｋ 明るい"] {
            let page = try await store.search(query: query)
            precondition(page.items.contains { $0.id == first.id }, "Search missing: \(query)")
        }
        for query in ["100_", "a%b", "' OR 1=1 --", "見つからない"] {
            let page = try await store.search(query: query); precondition(page.items.isEmpty, "LIKE/injection incorrectly matched")
        }
        let tags = try await store.tags()
        let kick = tags.first { MaterialStore.normalize($0.name) == "kick" }!
        let filtered = try await store.search(tagID: kick.id); precondition(filtered.total == 1 && filtered.items[0].id == first.id)
        let recordAfter = try await store.restore(first.id)
        precondition(recordAfter.record == first)
        let reopened = MaterialStore(root: libraryRoot)
        let persisted = try await reopened.search(query: "雨の日")
        precondition(persisted.items[0].annotations == saved)
        do { _ = try await store.updateAnnotations(first.id, tags: [], note: String(repeating: "x", count: 4001)); fatalError("Long note accepted") } catch {}
        do { _ = try await store.updateAnnotations(first.id, tags: [String(repeating: "字", count: 41)], note: ""); fatalError("Long tag accepted") } catch {}
        let afterInvalid = try await store.search(query: "雨の日"); precondition(afterInvalid.items[0].annotations == saved)
        // Comparison candidates are cropped PCM, not UI timers gating long source files.
        var comparison: MaterialComparison? = try await store.comparison(first.id)
        let previewDirectory = comparison!.directory
        for kind in MaterialPreviewKind.allCases {
            let source = try AVAudioFile(forReading: kind == .original ? original : stem)
            let candidate = try AVAudioFile(forReading: comparison!.url(kind))
            precondition(candidate.length == 88200)
            let a = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 88200)!
            let b = AVAudioPCMBuffer(pcmFormat: candidate.processingFormat, frameCapacity: 88200)!
            source.framePosition = 22050; try source.read(into: a); try candidate.read(into: b)
            for c in 0..<2 { for f in 0..<88200 { precondition(a.floatChannelData![c][f] == b.floatChannelData![c][f]) } }
        }
        comparison = nil; precondition(!fm.fileExists(atPath: previewDirectory.path))
        // Populate additional valid metadata fixtures to exercise SQL paging without recopying audio.
        let sourceID = try execute(database, "SELECT id FROM sources")[0][0]
        for _ in 0..<51 {
            var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
            let id = UUID().uuidString, runID = UUID().uuidString, stemID = UUID().uuidString
            payload["id"] = id
            var provenance = payload["provenance"] as! [String: Any]; provenance["runID"] = runID; payload["provenance"] = provenance
            let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            let metadata = String(decoding: try JSONSerialization.data(withJSONObject: provenance), as: UTF8.self)
            _ = try execute(database, "INSERT INTO runs VALUES(?,?,?,?)", [runID, sourceID, first.originalHash, metadata])
            _ = try execute(database, "INSERT INTO stems VALUES(?,?,?,?)", [stemID, runID, "drums", first.stemHash])
            _ = try execute(database, "INSERT INTO materials VALUES(?,?,?,?,?,?,?,?)", [id, stemID, String(first.startFrame), String(first.endFrame), first.name, String(first.created.timeIntervalSince1970), first.clipHash, json])
            _ = try execute(database, "INSERT INTO material_annotations VALUES(?,?,?)", [id, "", MaterialStore.normalize(first.name + "\n" + p.sourceName)])
        }
        let page1 = try await store.search(), page2 = try await store.search(offset: 50)
        precondition(page1.total == 53 && page1.items.count == 50 && page2.items.count == 3)
        precondition(Set((page1.items + page2.items).map(\.id)).count == 53)
        let player = PlayerModel(materialStore: store), library = player.materials
        library.refresh()
        for _ in 0..<200 where library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        _ = library.select(MaterialItem(record: first, annotations: saved))
        library.noteText = "未保存"
        precondition(!library.select(MaterialItem(record: second, annotations: .empty)))
        library.query = "missing"; library.query = "雨の日"
        for _ in 0..<200 where library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.total == 1 && library.records[0].id == first.id && library.noteText == "未保存" && library.annotationDirty)
        library.discardAnnotations()
        if CommandLine.arguments.contains("--playback") {
            await player.load(stem); await player.prepareInstrument()
            let sample = player.instrumentSample!, priorURL = player.asset!.url
            player.previewMaterial(.clip)
            for _ in 0..<300 where library.previewLoading { try await Task.sleep(nanoseconds: 10_000_000) }
            precondition(library.previewKind == .clip && library.previewDuration == 2)
            library.seekPreview(0.45); player.previewMaterial(.original)
            precondition(library.previewKind == .original && abs(library.previewPosition - 0.45) < 0.1)
            player.previewMaterial(.stem)
            precondition(library.previewKind == .stem && abs(library.previewPosition - 0.45) < 0.15)
            precondition(player.asset?.url == priorURL && player.instrumentSample?.buffer === sample.buffer && player.instrumentDirty)
            player.stop(); precondition(library.previewKind == nil && !library.previewLoading)
            player.previewMaterial(.original); library.stopPreview()
            try await Task.sleep(nanoseconds: 100_000_000)
            precondition(library.previewKind == nil && !library.previewLoading)
            player.previewMaterial(.stem)
            for _ in 0..<300 where library.previewLoading { try await Task.sleep(nanoseconds: 10_000_000) }
            library.seekPreview(1.97)
            for _ in 0..<100 where library.previewKind != nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            precondition(library.previewKind == nil)
            player.previewMaterial(.clip)
            for _ in 0..<300 where library.previewLoading { try await Task.sleep(nanoseconds: 10_000_000) }
            library.query = "different"; precondition(library.previewKind == nil && !library.previewLoading)
        }
        // Removing all rows from the last page clamps back to the previous page.
        library.query = ""
        for _ in 0..<300 where library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        library.page(1)
        for _ in 0..<300 where library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.offset == 50 && library.records.count == 3)
        for item in library.records { try await store.setTrashed(item.id, trashed: true) }
        library.refresh(resetPage: false)
        for _ in 0..<300 where library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.offset == 0 && library.total == 50 && library.records.count == 50)
        library.cancel(); player.cleanup()
        print("PASS: material schema migration/backup/rollback, persistent tags/notes, Unicode/literal search/filter/paging, exact comparison PCM/ranges, stale search/dirty preservation and comparison playback lifecycle")
    }
}
