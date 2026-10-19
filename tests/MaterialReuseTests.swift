import Foundation
import AVFoundation
import SQLite3

enum MaterialReuseTests {
    @MainActor static func run() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SonicForge-MaterialReuse-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let input = root.appendingPathComponent("input.wav")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            let file = try AVAudioFile(forWriting: input, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132300)!
            buffer.frameLength = 132300
            for c in 0..<2 { for f in 0..<132300 { buffer.floatChannelData![c][f] = Float(sin(Double(f + c) * .pi * 880 / 44100) * 0.1) } }
            try file.write(from: buffer)
        }
        let p = MaterialProvenance(sourceName: "検証用の元曲", inputSHA256: try MaterialHash.file(input), runID: UUID().uuidString,
            model: "htdemucs", backend: "mlx-metal", settings: .standard, weightSHA256: SeparationClient.weightHash,
            versions: ["fixture":"1"], gain: 1, preprocessing: "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1", stem: "drums", frames: 132300, sampleRate: 44100)
        let store = MaterialStore(root: root.appendingPathComponent("library"))
        let draft = try await store.prepare(origin: MaterialOrigin(provenance: p, input: input, original: input, stem: input, lease: nil),
            selection: AudioSelection(startFrame: 44100, endFrame: 110250), name: "親素材")
        let parent = try await store.commit(draft.id)
        _ = try await store.updateAnnotations(parent.id, tags: ["ドラム"], note: "親のメモ")
        let player = PlayerModel(materialStore: store)
        let opened = await player.openMaterial(parent.id, clip: true)
        precondition(opened && player.editor.frameCount == 66150 && player.materialOrigin?.frameOffset == 44100)
        player.select(from: 1.0/3, to: 2.0/3)
        precondition(player.materialSelectionInSource == AudioSelection(startFrame: 66150, endFrame: 88200))
        let childDraft = try await store.prepare(origin: player.materialOrigin!, selection: player.editor.selection!, name: "子素材")
        let child = try await store.commit(childDraft.id)
        precondition(child.id != parent.id && child.parentMaterialID == parent.id && child.startFrame == 66150 && child.endFrame == 88200)
        let inherited = try await store.item(child.id)
        precondition(inherited.annotations.tags == ["ドラム"] && inherited.annotations.note == "親のメモ")
        _ = try await store.updateAnnotations(child.id, tags: ["子"], note: "子だけ変更")
        let intact = try await store.item(parent.id)
        precondition(intact.record == parent && intact.annotations.note == "親のメモ" && intact.annotations.tags == ["ドラム"])
        let childOpened = await player.openMaterial(child.id, clip: true); precondition(childOpened)
        player.select(from: 0.2, to: 0.6)
        await player.prepareInstrument()
        let provenance = player.instrumentProvenance!
        precondition(provenance.material.id == child.id && provenance.startFrame == 70560 && provenance.endFrame == 79380)
        let sample = player.instrumentSample!, frames = Int64(sample.buffer.frameLength)
        precondition(frames == 8820)
        // Later waveform selection must not rewrite an already-installed instrument's origin.
        player.select(from: 0, to: 0.1)
        precondition(player.instrumentProvenance == provenance)
        let file = root.appendingPathComponent("derived.sfinstrument")
        await player.saveInstrument(sample: sample, root: 60, to: file, remember: false)
        precondition(!player.instrumentDirty)
        let archive = try JSONDecoder().decode(InstrumentArchive.self, from: Data(contentsOf: file))
        precondition(archive.version == 5 && archive.provenance == provenance)
        let restored = try InstrumentDocument.load(file)
        precondition(restored.provenance == provenance)
        for c in 0..<2 { for f in 0..<Int(frames) { precondition(sample.buffer.floatChannelData![c][f] == restored.sample.buffer.floatChannelData![c][f]) } }
        try fm.removeItem(at: restored.directory)
        // Installed provenance also survives composition settings, history, AI, and embedded save/reload.
        let ensemble = EnsembleModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let instrument = EnsembleInstrument(sample: sample, root: 60, envelope: .standard, loop: SampleLoop(endFrame: frames), name: "派生楽器", provenance: provenance)
        let part = ensemble.addPart(instrument: instrument)!
        ensemble.setInstrumentSettings(part: part.id, root: 61, envelope: .standard, loop: instrument.loop)
        precondition(part.instrument?.provenance == provenance)
        precondition(ensemble.restoreSongEdit() && part.instrument?.provenance == provenance)
        precondition(ensemble.restoreSongEdit(redo: true) && part.instrument?.provenance == provenance)
        let brief = try ensemble.arrangementBrief(prompt: "検証")
        let proposal = try ArrangementGeneration.demo(brief)
        let ai = try ArrangementGeneration.materialize(proposal, brief: brief)
        precondition(ai.parts[0].instrument.provenance == provenance)
        let instructions = try brief.instructions
        precondition(!instructions.contains(p.inputSHA256) && !instructions.contains(p.sourceName))
        let song = root.appendingPathComponent("derived.sfensemble")
        let saved = await ensemble.save(to: song, remember: false); precondition(saved)
        let songArchive = try JSONSerialization.jsonObject(with: Data(contentsOf: song)) as! [String: Any]
        let archivedPart = (songArchive["parts"] as! [[String: Any]])[0]
        let archivedInstrument = archivedPart["instrument"] as! [String: Any]
        precondition(songArchive["version"] as? Int == 12 && archivedInstrument["version"] as? Int == 5)
        let songReload = try EnsembleDocument.load(song)
        precondition(songReload.parts[0].instrument.provenance == provenance)
        try EnsembleDocument.save(songReload, to: song)
        let again = try EnsembleDocument.load(song)
        precondition(again.parts[0].instrument.provenance == provenance)
        var oldSong = try JSONSerialization.jsonObject(with: Data(contentsOf: song)) as! [String: Any]
        oldSong["version"] = 11
        let badSong = root.appendingPathComponent("bad.sfensemble")
        try JSONSerialization.data(withJSONObject: oldSong).write(to: badSong)
        do { _ = try EnsembleDocument.load(badSong); fatalError("Old ensemble version accepted provenance") } catch {}
        // Missing library: the embedded audio and portable origin remain usable; no catalog is fabricated.
        let missingRoot = root.appendingPathComponent("missing-library")
        let portable = PlayerModel(materialStore: MaterialStore(root: missingRoot))
        let portableOpened = await portable.loadInstrument(file, remember: false)
        precondition(portableOpened && portable.instrumentProvenance == provenance && portable.materialOrigin == nil)
        precondition(!fm.fileExists(atPath: missingRoot.appendingPathComponent("catalog.sqlite").path))
        portable.select(from: 0.25, to: 0.75)
        await portable.prepareInstrument()
        precondition(portable.instrumentProvenance?.startFrame == 72765 && portable.instrumentProvenance?.endFrame == 77175)
        if CommandLine.arguments.contains("--playback") {
            portable.playNote(60); precondition(portable.soundingVoices > 0); portable.stop()
        }
        let nested = root.appendingPathComponent("nested.sfinstrument")
        await portable.saveInstrument(sample: portable.instrumentSample!, root: 60, to: nested, remember: false)
        let nestedRestored = try InstrumentDocument.load(nested)
        precondition(nestedRestored.provenance?.startFrame == 72765)
        try fm.removeItem(at: nestedRestored.directory)
        // An invalid portable range must reject atomically and preserve the previous instrument.
        var bad = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var source = bad["provenance"] as! [String: Any]; source["endFrame"] = provenance.endFrame + 1; bad["provenance"] = source
        let corrupt = root.appendingPathComponent("bad.sfinstrument")
        try JSONSerialization.data(withJSONObject: bad).write(to: corrupt)
        let prior = portable.instrumentProvenance
        let rejected = await portable.loadInstrument(corrupt, remember: false)
        precondition(!rejected && portable.instrumentProvenance == prior)
        // Legacy instrument versions carry no origin, and still restore.
        let legacy = try InstrumentDocument.makeArchive(sample: sample, rootNote: 60, envelope: .standard)
        for version in 1...4 {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
            json["version"] = version
            let decoded = try JSONDecoder().decode(InstrumentArchive.self, from: JSONSerialization.data(withJSONObject: json))
            let loaded = try InstrumentDocument.restore(decoded)
            precondition(loaded.provenance == nil)
            try fm.removeItem(at: loaded.directory)
        }
        // Trash is visibility metadata only; shared audio, descendants and portable origins survive.
        let objects = root.appendingPathComponent("library/objects")
        func objectHashes() throws -> [String: String] {
            let urls = fm.enumerator(at: objects, includingPropertiesForKeys: [.isRegularFileKey])!
            var hashes: [String: String] = [:]
            for case let url as URL in urls where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                hashes[url.path] = try MaterialHash.file(url)
            }
            return hashes
        }
        let beforeTrash = try objectHashes()
        try await store.setTrashed(parent.id, trashed: true)
        let trashedParent = try await store.item(parent.id)
        precondition(trashedParent.trashedAt != nil && trashedParent.record == parent && trashedParent.annotations == intact.annotations)
        try await store.setTrashed(parent.id, trashed: true)
        let repeated = try await store.item(parent.id)
        precondition(repeated.trashedAt == trashedParent.trashedAt)
        let active = try await store.search(), trash = try await store.search(query: "親のメモ", trashed: true)
        precondition(active.total == 1 && active.items[0].id == child.id && trash.total == 1 && trash.items[0].id == parent.id)
        let activeTags = try await store.tags(), trashTags = try await store.tags(trashed: true)
        precondition(activeTags.map(\.name) == ["子"] && trashTags.map(\.name) == ["ドラム"])
        let childAfterTrash = try await store.restore(child.id)
        precondition(childAfterTrash.record == child)
        let parentAfterTrash = try await store.restore(parent.id)
        precondition(parentAfterTrash.record == parent)
        let comparisonAfterTrash = try await store.comparison(child.id)
        precondition(comparisonAfterTrash.record == child)
        let duplicate = try await store.prepare(origin: parentAfterTrash.origin, selection: parent.selection, name: "同一区間")
        do { _ = try await store.commit(duplicate.id); fatalError("Trashed duplicate silently restored") } catch {}
        let stillTrashed = try await store.item(parent.id); precondition(stillTrashed.trashedAt != nil)
        try await store.setTrashed(child.id, trashed: true)
        let instrumentOpened = await player.loadInstrument(file, remember: false)
        precondition(instrumentOpened && player.materialOrigin != nil && player.instrumentProvenance == provenance)
        let reopenedStore = MaterialStore(root: root.appendingPathComponent("library"))
        let persistedTrash = try await reopenedStore.search(trashed: true)
        precondition(persistedTrash.total == 2 && persistedTrash.items.first(where: { $0.id == parent.id })?.trashedAt == trashedParent.trashedAt)
        let library = player.materials
        await library.reveal(parent.id)
        precondition(library.showingTrash && library.selected?.id == parent.id)
        library.noteText = "未保存"
        precondition(!library.showTrash(false))
        library.changeTrashState(); precondition(!library.busy)
        library.discardAnnotations()
        if CommandLine.arguments.contains("--playback") {
            player.previewMaterial(.clip)
            for _ in 0..<300 where library.previewLoading { try await Task.sleep(nanoseconds: 10_000_000) }
            precondition(library.previewKind == .clip)
        }
        library.changeTrashState()
        precondition(library.previewKind == nil && !library.previewLoading)
        for _ in 0..<300 where library.busy || library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.error == nil && library.selected == nil)
        let restoredParent = try await store.item(parent.id)
        precondition(restoredParent.trashedAt == nil && restoredParent.record == parent && restoredParent.annotations == intact.annotations)
        try await store.setTrashed(child.id, trashed: false)
        try await store.setTrashed(child.id, trashed: false)
        do { try await store.setTrashed(UUID().uuidString, trashed: true); fatalError("Missing material accepted") } catch {}
        let cancelledTrash = Task { try await store.setTrashed(parent.id, trashed: true) }
        cancelledTrash.cancel()
        do { try await cancelledTrash.value; fatalError("Cancelled trash mutation succeeded") } catch is CancellationError {}
        let afterCancellation = try await store.item(parent.id)
        precondition(afterCancellation.trashedAt == nil)
        // Saving pending annotations may immediately start a trash mutation.
        await library.reveal(parent.id)
        library.noteText = "保存してから移動"
        var continued = false
        library.saveAnnotations {
            precondition(!library.busy)
            library.changeTrashState()
            precondition(library.busy)
            continued = true
        }
        for _ in 0..<300 where !continued || library.busy || library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        let savedThenTrashed = try await store.item(parent.id)
        precondition(continued && library.error == nil && savedThenTrashed.trashedAt != nil && savedThenTrashed.annotations.note == "保存してから移動")
        try await store.setTrashed(parent.id, trashed: false)
        _ = try await store.updateAnnotations(parent.id, tags: intact.annotations.tags, note: intact.annotations.note)
        let checkedHashes = try objectHashes(); precondition(checkedHashes == beforeTrash)
        // Upgrade a shipped v2 catalog without changing payloads, notes or objects.
        let catalog = root.appendingPathComponent("library/catalog.sqlite")
        func sql(_ statement: String) {
            var db: OpaquePointer?; precondition(sqlite3_open(catalog.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
        }
        sql("DROP TABLE material_reclaims; DROP TABLE material_retentions; DROP TABLE material_tombstones; DROP TABLE material_trash; PRAGMA user_version=2")
        // A failed v2 migration preserves its prior schema and payloads.
        let brokenRoot = root.appendingPathComponent("broken-v2")
        try fm.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
        let brokenCatalog = brokenRoot.appendingPathComponent("catalog.sqlite")
        try fm.copyItem(at: catalog, to: brokenCatalog)
        do {
            var db: OpaquePointer?; precondition(sqlite3_open(brokenCatalog.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            precondition(sqlite3_exec(db, "CREATE TABLE material_trash(collision TEXT)", nil, nil, nil) == SQLITE_OK)
        }
        do { _ = try await MaterialStore(root: brokenRoot).search(); fatalError("Broken v2 migration accepted") } catch {}
        do {
            var db: OpaquePointer?; precondition(sqlite3_open(brokenCatalog.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            precondition(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 2)
        }
        let brokenBackups = try fm.contentsOfDirectory(at: brokenRoot.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        precondition(brokenBackups.count == 1)
        let migratedStore = MaterialStore(root: root.appendingPathComponent("library"))
        let migrated = try await migratedStore.search()
        precondition(migrated.total == 2 && migrated.items.allSatisfy { $0.trashedAt == nil })
        let migratedParent = try await migratedStore.item(parent.id)
        precondition(migratedParent.record == parent && migratedParent.annotations == intact.annotations)
        let backups = try fm.contentsOfDirectory(at: root.appendingPathComponent("library/backups"), includingPropertiesForKeys: nil)
        precondition(backups.count == 1 && backups[0].lastPathComponent.hasPrefix("catalog-v2-"))
        let migratedHashes = try objectHashes(); precondition(migratedHashes == beforeTrash)
        library.cancel()
        // A normal source swap clears both live and installed provenance.
        await player.load(input)
        precondition(player.instrumentProvenance == nil && player.waveformProvenance == nil && player.materialOrigin == nil)
        portable.cleanup(); player.cleanup(); ensemble.stop()
        print("PASS: material clip reedit/absolute offsets/parent annotations, v5 portable provenance/legacy/range rejection, immutable installed origin, v12 composition/history/AI and missing-library reuse; trash/restore persistence, shared blobs/ancestry, dedup, scoped search/tags, dirty guards, preview cancellation and v2 migration")
    }
}
