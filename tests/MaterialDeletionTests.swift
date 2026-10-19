import Foundation
import AVFoundation
import SQLite3

enum MaterialDeletionTests {
    private struct Fixture {
        let root: URL
        let origin: MaterialOrigin
    }
    private static func fixture(_ root: URL) throws -> Fixture {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func audio(_ name: String, gain: Double) throws -> URL {
            let url = root.appendingPathComponent(name)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88200)!
            buffer.frameLength = 88200
            for c in 0..<2 { for f in 0..<88200 { buffer.floatChannelData![c][f] = Float(gain * sin(Double(f + c) * .pi * 880 / 44100)) } }
            try file.write(from: buffer)
            return url
        }
        let input = try audio("source.wav", gain: 0.2), stem = try audio("stem.wav", gain: 0.1)
        let p = MaterialProvenance(sourceName: "完全削除の検証", inputSHA256: try MaterialHash.file(input), runID: UUID().uuidString,
            model: "htdemucs", backend: "mlx-metal", settings: .standard, weightSHA256: SeparationClient.weightHash,
            versions: ["fixture":"1"], gain: 1, preprocessing: "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1", stem: "drums", frames: 88200, sampleRate: 44100)
        return Fixture(root: root.appendingPathComponent("library"), origin: MaterialOrigin(provenance: p, input: input, original: input, stem: stem, lease: nil))
    }
    private static func save(_ store: MaterialStore, _ origin: MaterialOrigin, _ start: Int64 = 0, _ end: Int64 = 44100, _ name: String = "素材") async throws -> MaterialRecord {
        let draft = try await store.prepare(origin: origin, selection: AudioSelection(startFrame: start, endFrame: end), name: name)
        return try await store.commit(draft.id)
    }
    private static func files(_ root: URL) throws -> [String: String] {
        let folder = root.appendingPathComponent("objects")
        var result: [String: String] = [:]
        for case let url as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])! {
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true { result[url.path] = try MaterialHash.file(url) }
        }
        return result
    }
    @MainActor static func run() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SonicForge-Deletion-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        // Batch planning treats selected parents/children as one set and counts shared audio once.
        let batchFixture = try fixture(root.appendingPathComponent("batch")), batchStore = MaterialStore(root: batchFixture.root)
        let batchParent = try await save(batchStore, batchFixture.origin, 0, 44100, "一括親")
        var batchOrigin = batchFixture.origin; batchOrigin.record = batchParent
        let batchChild = try await save(batchStore, batchOrigin, 11025, 22050, "一括子")
        let batchOther = try await save(batchStore, batchFixture.origin, 44100, 55125, "選択外")
        for r in [batchParent, batchChild, batchOther] { try await batchStore.setTrashed(r.id, trashed: true) }
        let batchIDs: Set<String> = [batchParent.id, batchChild.id]
        let withOther = try await batchStore.prepareBatchDeletion(batchIDs)
        precondition(withOther.records.count == 2 && withOther.references.contains("素材: 選択外"))
        precondition(!withOther.files.contains { $0.hash == batchParent.originalHash || $0.hash == batchParent.stemHash })
        let allIDs = batchIDs.union([batchOther.id])
        let together = try await batchStore.prepareBatchDeletion(allIDs)
        let uniqueHashes = Set([batchParent, batchChild, batchOther].flatMap { $0.audioHashes })
        precondition(Set(together.files.map(\.hash)) == uniqueHashes && together.files.count == uniqueHashes.count)
        let logicalBytes = try fm.enumerator(at: batchFixture.root.appendingPathComponent("objects"), includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])!.allObjects.compactMap { $0 as? URL }.reduce(Int64(0)) { sum, url in
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]); return sum + (v.isRegularFile == true ? Int64(v.fileSize ?? 0) : 0)
        }
        precondition(together.bytes == logicalBytes)
        // Restoring any selected member invalidates the entire plan without deleting another member.
        let beforeBatch = try files(batchFixture.root)
        try await batchStore.setTrashed(batchChild.id, trashed: false)
        do { _ = try await batchStore.deletePermanently(together); fatalError("Batch ignored restoration") } catch {}
        let unchangedBatch = try files(batchFixture.root); precondition(unchangedBatch == beforeBatch)
        for r in [batchParent, batchChild, batchOther] { let i = try await batchStore.item(r.id); precondition(i.deletedAt == nil) }
        do { _ = try await batchStore.prepareBatchDeletion(allIDs); fatalError("Batch accepted active material") } catch {}
        do { _ = try await batchStore.prepareBatchDeletion([]); fatalError("Batch accepted empty selection") } catch {}
        do { _ = try await batchStore.prepareBatchDeletion(Set((0...50).map { String($0) })); fatalError("Batch accepted more than 50") } catch {}
        do { _ = try await batchStore.prepareBatchDeletion([batchParent.id, "missing"]); fatalError("Batch accepted missing material") } catch {}
        try await batchStore.setTrashed(batchChild.id, trashed: true)
        let cancelBatchPlan = try await batchStore.prepareBatchDeletion(allIDs)
        let cancelledBatch = Task { try await batchStore.deletePermanently(cancelBatchPlan) }; cancelledBatch.cancel()
        do { _ = try await cancelledBatch.value; fatalError("Cancelled batch committed") } catch {}
        for r in [batchParent, batchChild, batchOther] { let i = try await batchStore.item(r.id); precondition(i.deletedAt == nil) }
        try await batchStore.setTrashed(batchChild.id, trashed: true)
        let batchPin = MaterialProtection(record: batchChild, label: "一括の楽器・構成")
        let pinnedBatch = try await batchStore.prepareBatchDeletion(allIDs, protections: [batchPin])
        precondition(pinnedBatch.references.contains(batchPin.label) && !pinnedBatch.files.contains { $0.hash == batchParent.clipHash })
        let batchRead = try await batchStore.restore(batchOther.id)
        do { _ = try await batchStore.deletePermanently(pinnedBatch); fatalError("Batch ignored new reader") } catch {}
        precondition(batchRead.record == batchOther)
        let readerBatch = try await batchStore.prepareBatchDeletion(allIDs)
        precondition(readerBatch.bytes == 0)
        // A metadata failure rolls the complete batch back.
        let batchDB = try await batchStore.database()
        try batchDB.execute("CREATE TRIGGER fail_batch BEFORE INSERT ON material_tombstones WHEN NEW.id='\(allIDs.sorted().last!)' BEGIN SELECT RAISE(ABORT,'injected batch failure'); END")
        let failingBatch = try await batchStore.prepareBatchDeletion(allIDs)
        do { _ = try await batchStore.deletePermanently(failingBatch); fatalError("Batch metadata failure ignored") } catch {}
        for r in [batchParent, batchChild, batchOther] { let i = try await batchStore.item(r.id); precondition(i.deletedAt == nil && i.trashedAt != nil) }
        let unchangedAfterFailure = try files(batchFixture.root); precondition(unchangedAfterFailure == beforeBatch)
        try batchDB.execute("DROP TRIGGER fail_batch")
        let safeBatch = try await batchStore.prepareBatchDeletion(allIDs)
        _ = try await batchStore.deletePermanently(safeBatch)
        for r in [batchParent, batchChild, batchOther] { let i = try await batchStore.item(r.id); precondition(i.deletedAt != nil) }
        let unchangedAfterDelete = try files(batchFixture.root); precondition(unchangedAfterDelete == beforeBatch)

        // Interrupted audio collection is journaled once per hash and retryable from one deleted record.
        let partialBatchFixture = try fixture(root.appendingPathComponent("partial-batch"))
        let failHash = partialBatchFixture.origin.provenance.inputSHA256
        let partialBatchStore = MaterialStore(root: partialBatchFixture.root, reclaimFile: { url in
            if url.lastPathComponent.hasPrefix(failHash) { throw AudioError.invalid("injected batch unlink failure") }
            try FileManager.default.removeItem(at: url)
        })
        let b1 = try await save(partialBatchStore, partialBatchFixture.origin, 0, 11025)
        let b2 = try await save(partialBatchStore, partialBatchFixture.origin, 22050, 33075)
        for r in [b1, b2] { try await partialBatchStore.setTrashed(r.id, trashed: true) }
        let partialBatchPlan = try await partialBatchStore.prepareBatchDeletion([b1.id, b2.id])
        let batchResult = try await partialBatchStore.deletePermanently(partialBatchPlan)
        precondition(batchResult.remainingFiles == 1)
        let restartBatch = MaterialStore(root: partialBatchFixture.root)
        let batchPending = try await restartBatch.pendingReclaims()
        precondition(batchPending.count == 1 && batchPending[0].id == partialBatchPlan.record.id)
        let retryBatchPlan = try await restartBatch.prepareDeletion(batchPending[0].id)
        let recoveredBatch = try await restartBatch.deletePermanently(retryBatchPlan)
        precondition(recoveredBatch.remainingFiles == 0 && batchResult.reclaimedBytes + recoveredBatch.reclaimedBytes == partialBatchPlan.bytes)
        for r in [b1, b2] { let i = try await restartBatch.item(r.id); precondition(i.deletedAt != nil) }
        // Model selection is limited to visible trash rows and cleared on search/page/scope changes.
        let batchModelFixture = try fixture(root.appendingPathComponent("batch-model")), batchModelStore = MaterialStore(root: batchModelFixture.root)
        let m1 = try await save(batchModelStore, batchModelFixture.origin, 0, 11025)
        let m2 = try await save(batchModelStore, batchModelFixture.origin, 22050, 33075)
        for r in [m1, m2] { try await batchModelStore.setTrashed(r.id, trashed: true) }
        let batchModel = MaterialLibraryModel(store: batchModelStore)
        _ = batchModel.showTrash(true)
        for _ in 0..<300 where batchModel.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        batchModel.setDeletionSelected("unknown", selected: true); precondition(batchModel.deletionSelection.isEmpty)
        batchModel.selectPageForDeletion(true); precondition(batchModel.deletionSelection.count == 2)
        batchModel.reviewBatchDeletion(protections: [], files: [])
        for _ in 0..<300 where batchModel.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(batchModel.deletionPlan?.records.count == 2)
        batchModel.dismissDeletion(); precondition(batchModel.deletionSelection.count == 2)
        batchModel.query = "検索変更"; precondition(batchModel.deletionSelection.isEmpty)
        batchModel.query = ""
        for _ in 0..<300 where batchModel.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        batchModel.selectPageForDeletion(true)
        batchModel.reviewBatchDeletion(protections: [], files: [])
        for _ in 0..<300 where batchModel.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        batchModel.confirmDeletion(protections: [], files: [])
        for _ in 0..<300 where batchModel.busy || batchModel.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(batchModel.total == 0 && batchModel.deletionSelection.isEmpty && batchModel.message.contains("2件"))
        // Historical protection release previews capacity, preserves live readers, and revalidates state.
        let releaseFixture = try fixture(root.appendingPathComponent("release"))
        let releaseStore = MaterialStore(root: releaseFixture.root)
        let retained = try await save(releaseStore, releaseFixture.origin)
        let pin = MaterialProtection(record: retained, label: "過去の楽器")
        try await releaseStore.retain([pin])
        let activeReview = try await releaseStore.protectionReview(retained.id, protections: [], files: [])
        guard let entry = activeReview.entries.first else { throw AudioError.invalid("保護一覧が空です") }
        let activeRelease = try await releaseStore.prepareRelease(entry, materialID: retained.id, protections: [], files: [])
        guard activeRelease.after.bytes == 0 else { throw AudioError.invalid("保存素材の音声を回収候補にしました") }
        try await releaseStore.setTrashed(retained.id, trashed: true)
        let deletePlan = try await releaseStore.prepareDeletion(retained.id)
        _ = try await releaseStore.deletePermanently(deletePlan)
        let releasePlan = try await releaseStore.prepareRelease(entry, materialID: retained.id, protections: [], files: [])
        guard releasePlan.after.bytes > 0, releasePlan.before.bytes == 0 else { throw AudioError.invalid("解除容量の計算が不正です") }
        let blocked = try await releaseStore.prepareRelease(entry, materialID: retained.id, protections: [pin], files: [])
        guard blocked.blocked else { throw AudioError.invalid("使用中の保護を解除可能にしました") }
        do {
            try await releaseStore.releaseProtection(blocked, protections: [pin], files: [])
            throw AudioError.invalid("使用中保護の解除が成功しました")
        } catch { guard error.localizedDescription.contains("使用中") else { throw error } }
        var reader: MaterialRestoration? = try await releaseStore.restore(retained.id, includeDeleted: true)
        do {
            try await releaseStore.releaseProtection(releasePlan, protections: [], files: [])
            throw AudioError.invalid("古い解除計画が成功しました")
        } catch { guard error.localizedDescription.contains("変わりました") else { throw error } }
        guard reader != nil else { throw AudioError.invalid("読者がありません") }
        reader = nil
        let fresh = try await releaseStore.prepareRelease(entry, materialID: retained.id, protections: [], files: [])
        let beforeRelease = try files(releaseFixture.root)
        try await releaseStore.releaseProtection(fresh, protections: [], files: [])
        guard try files(releaseFixture.root) == beforeRelease else { throw AudioError.invalid("解除時に音声を削除しました") }
        let restartedRelease = MaterialStore(root: releaseFixture.root)
        let releasedReview = try await restartedRelease.protectionReview(retained.id, protections: [], files: [])
        guard releasedReview.entries.isEmpty else { throw AudioError.invalid("解除を永続化できませんでした") }
        let deletedHistory = try await restartedRelease.protectedDeletedItems()
        guard deletedHistory.contains(where: { $0.id == retained.id }) else { throw AudioError.invalid("解除後の回収入口が消えました") }
        let reclaim = try await restartedRelease.prepareDeletion(retained.id)
        guard reclaim.bytes == fresh.after.bytes else { throw AudioError.invalid("解除後の回収容量が一致しません") }
        _ = try await restartedRelease.deletePermanently(reclaim)
        // Parent removal retains the entire lineage used by the surviving child.
        let family = try fixture(root.appendingPathComponent("family")), store = MaterialStore(root: family.root)
        let parent = try await save(store, family.origin, 0, 44100, "親")
        _ = try await store.updateAnnotations(parent.id, tags: ["検証"], note: "メモ")
        var derivedOrigin = family.origin; derivedOrigin.record = parent
        let child = try await save(store, derivedOrigin, 22050, 33075, "子")
        let baseline = try files(family.root)
        try await store.setTrashed(parent.id, trashed: true)
        let parentPlan = try await store.prepareDeletion(parent.id)
        precondition(parentPlan.bytes == 0 && parentPlan.references.contains("素材: 子"))
        let parentResult = try await store.deletePermanently(parentPlan)
        precondition(parentResult.reclaimedBytes == 0 && parentResult.remainingFiles == 0)
        let parentItem = try await store.item(parent.id)
        precondition(parentItem.deletedAt != nil && parentItem.record == parent && parentItem.annotations == .empty)
        do { _ = try await store.restore(parent.id); fatalError("Deleted material restored") } catch {}
        do { try await store.setTrashed(parent.id, trashed: false); fatalError("Deleted material untrashed") } catch {}
        var restoredChild: MaterialRestoration? = try await store.restore(child.id)
        precondition(restoredChild?.record == child)
        let afterParent = try files(family.root); precondition(afterParent == baseline)
        restoredChild = nil
        try await store.setTrashed(child.id, trashed: true)
        let childPlan = try await store.prepareDeletion(child.id)
        precondition(childPlan.files.count == baseline.count && childPlan.bytes > 0)
        let childResult = try await store.deletePermanently(childPlan)
        let emptied = try files(family.root)
        precondition(childResult.reclaimedBytes == childPlan.bytes && childResult.remainingFiles == 0 && emptied.isEmpty)
        let childItem = try await store.item(child.id)
        precondition(childItem.record.parentMaterialID == parent.id && childItem.deletedAt != nil)
        let noTrash = try await store.search(trashed: true); precondition(noTrash.total == 0)
        // Reimport of an identical interval gets a new identity; tombstone ancestry is not overwritten.
        let recreated = try await save(store, family.origin)
        precondition(recreated.id != parent.id)
        let oldParent = try await store.item(parent.id); precondition(oldParent.record == parent && oldParent.deletedAt != nil)
        let sharedAfterReimport = try await store.prepareDeletion(parent.id)
        precondition(sharedAfterReimport.bytes == 0)

        // Preview cancellation does not mutate records; restored/changed data invalidates a prior plan.
        let stale = try fixture(root.appendingPathComponent("stale")), staleStore = MaterialStore(root: stale.root)
        let r = try await save(staleStore, stale.origin)
        try await staleStore.setTrashed(r.id, trashed: true)
        let before = try files(stale.root), preview = try await staleStore.prepareDeletion(r.id)
        precondition(preview.bytes > 0)
        try await staleStore.setTrashed(r.id, trashed: false)
        do { _ = try await staleStore.deletePermanently(preview); fatalError("Restored item deleted by stale plan") } catch {}
        try await staleStore.setTrashed(r.id, trashed: true)
        let notePlan = try await staleStore.prepareDeletion(r.id)
        _ = try await staleStore.updateAnnotations(r.id, tags: [], note: "変更")
        do { _ = try await staleStore.deletePermanently(notePlan); fatalError("Changed metadata deleted") } catch {}
        let leasePlan = try await staleStore.prepareDeletion(r.id)
        var lease: MaterialRestoration? = try await staleStore.restore(r.id)
        precondition(lease?.record == r)
        do { _ = try await staleStore.deletePermanently(leasePlan); fatalError("New reader ignored") } catch {}
        let held = try await staleStore.prepareDeletion(r.id)
        precondition(held.bytes == 0 && held.protectedFiles > 0)
        let heldResult = try await staleStore.deletePermanently(held); precondition(heldResult.reclaimedBytes == 0)
        let stillPresent = try files(stale.root); precondition(stillPresent == before)
        lease = nil
        let afterLease = try await staleStore.prepareDeletion(r.id)
        precondition(afterLease.bytes > 0 && afterLease.alreadyDeleted)
        let cancelled = Task { try await staleStore.deletePermanently(afterLease) }; cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled deletion succeeded") } catch is CancellationError {}
        let afterCancel = try files(stale.root); precondition(afterCancel == before)
        _ = try await staleStore.deletePermanently(afterLease)

        // An archived instrument pins its material and ancestry; its PCM and origin remain usable.
        let pinned = try fixture(root.appendingPathComponent("pinned")), pinnedStore = MaterialStore(root: pinned.root)
        let pinnedRecord = try await save(pinnedStore, pinned.origin)
        let provenance = InstrumentProvenance(material: pinnedRecord, startFrame: 0, endFrame: 44100)
        let sample = try InstrumentSample.load(url: pinned.origin.stem, selection: pinnedRecord.selection)
        let instrumentURL = root.appendingPathComponent("kept.sfinstrument")
        try InstrumentDocument.save(sample: sample, rootNote: 60, provenance: provenance, to: instrumentURL)
        let instrumentHash = try MaterialHash.file(instrumentURL), pinnedBefore = try files(pinned.root)
        try await pinnedStore.setTrashed(pinnedRecord.id, trashed: true)
        let unpinnedPlan = try await pinnedStore.prepareDeletion(pinnedRecord.id)
        let protected = try await pinnedStore.prepareDeletion(pinnedRecord.id, files: [instrumentURL])
        let fileReview = try await pinnedStore.protectionReview(pinnedRecord.id, protections: [], files: [instrumentURL])
        guard let fileEntry = fileReview.entries.first else { throw AudioError.invalid("保存ファイル参照がありません") }
        let fileRelease = try await pinnedStore.prepareRelease(fileEntry, materialID: pinnedRecord.id, protections: [], files: [instrumentURL])
        guard fileRelease.blocked else { throw AudioError.invalid("登録済みファイルの保護が解除可能です") }
        do {
            try await pinnedStore.releaseProtection(fileRelease, protections: [], files: [instrumentURL])
            throw AudioError.invalid("登録済みファイルの保護解除が成功しました")
        } catch { guard error.localizedDescription.contains("使用中") else { throw error } }
        do { _ = try await pinnedStore.deletePermanently(unpinnedPlan); fatalError("New instrument retention ignored") } catch {}
        precondition(protected.bytes == 0 && protected.references.contains(where: { $0.contains("kept.sfinstrument") }))
        _ = try await pinnedStore.deletePermanently(protected, files: [instrumentURL])
        let pinnedAfter = try files(pinned.root), unchangedInstrument = try MaterialHash.file(instrumentURL)
        precondition(pinnedBefore == pinnedAfter && unchangedInstrument == instrumentHash)
        let loaded = try InstrumentDocument.load(instrumentURL)
        precondition(loaded.provenance == provenance)
        let origin = try await pinnedStore.resolve(provenance)!
        let newChild = try await save(pinnedStore, origin, 0, 11025, "削除済み素材からの派生")
        precondition(newChild.parentMaterialID == pinnedRecord.id)
        try fm.removeItem(at: loaded.directory)
        let durable = MaterialStore(root: pinned.root)
        let durablePlan = try await durable.prepareDeletion(pinnedRecord.id)
        precondition(durablePlan.bytes == 0 && !durablePlan.references.isEmpty)
        let badArchive = root.appendingPathComponent("unreadable.sfinstrument")
        try Data("{}".utf8).write(to: badArchive)
        do { _ = try await durable.prepareDeletion(pinnedRecord.id, files: [badArchive]); fatalError("Unreadable registered file ignored") } catch {}

        do {
            _ = try await durable.prepareRelease(fileEntry, materialID: pinnedRecord.id, protections: [], files: [badArchive])
            throw AudioError.invalid("不明ファイルを無視して解除を準備しました")
        } catch { guard error.localizedDescription.contains("確認できない") else { throw error } }

        // File failures after metadata commit leave an explicit, restartable reclaim journal.
        let partial = try fixture(root.appendingPathComponent("partial"))
        let failingHash = partial.origin.provenance.inputSHA256
        let partialStore = MaterialStore(root: partial.root, reclaimFile: { url in
            if url.lastPathComponent.hasPrefix(failingHash) { throw AudioError.invalid("injected unlink failure") }
            try FileManager.default.removeItem(at: url)
        })
        let partialRecord = try await save(partialStore, partial.origin)
        try await partialStore.setTrashed(partialRecord.id, trashed: true)
        let partialPlan = try await partialStore.prepareDeletion(partialRecord.id)
        let result = try await partialStore.deletePermanently(partialPlan)
        precondition(result.remainingFiles == 1 && result.reclaimedBytes > 0 && result.reclaimedBytes < partialPlan.bytes)
        let partiallyDeleted = try await partialStore.item(partialRecord.id); precondition(partiallyDeleted.deletedAt != nil)
        let retryStore = MaterialStore(root: partial.root)
        let pendingAfterRestart = try await retryStore.pendingReclaims()
        precondition(pendingAfterRestart.count == 1 && pendingAfterRestart[0].id == partialRecord.id)
        let retry = try await retryStore.prepareDeletion(partialRecord.id)
        precondition(retry.alreadyDeleted && retry.files.count == 1)
        let retried = try await retryStore.deletePermanently(retry)
        precondition(retried.remainingFiles == 0 && retried.reclaimedBytes + result.reclaimedBytes == partialPlan.bytes)
        let noPending = try await retryStore.pendingReclaims(); precondition(noPending.isEmpty)
        // Source files outside managed objects are untouched.
        let sourceHash = try MaterialHash.file(partial.origin.input); precondition(sourceHash == failingHash)

        // Symlinks cannot turn a reclaim candidate into a deletion outside objects.
        let links = try fixture(root.appendingPathComponent("links")), linkStore = MaterialStore(root: links.root)
        let linkRecord = try await save(linkStore, links.origin)
        try await linkStore.setTrashed(linkRecord.id, trashed: true)
        let linkPlan = try await linkStore.prepareDeletion(linkRecord.id)
        let victim = linkPlan.files.first { $0.hash == linkRecord.inputHash }!
        let managed = links.root.appendingPathComponent(victim.path)
        try fm.removeItem(at: managed); try fm.createSymbolicLink(at: managed, withDestinationURL: links.origin.input)
        do { _ = try await linkStore.deletePermanently(linkPlan); fatalError("Symlink reclaim accepted") } catch {}
        let retainedItem = try await linkStore.item(linkRecord.id)
        precondition(retainedItem.deletedAt == nil && retainedItem.trashedAt != nil)
        let outsideHash = try MaterialHash.file(links.origin.input); precondition(outsideHash == linkRecord.inputHash)

        // Migrate shipped v3 with its trash/annotations intact, and fail closed on a DDL collision.
        let migration = try fixture(root.appendingPathComponent("migration")), oldStore = MaterialStore(root: migration.root)
        let oldRecord = try await save(oldStore, migration.origin)
        _ = try await oldStore.updateAnnotations(oldRecord.id, tags: ["残す"], note: "移行前")
        try await oldStore.setTrashed(oldRecord.id, trashed: true)
        let oldItem = try await oldStore.item(oldRecord.id), oldFiles = try files(migration.root)
        func execute(_ catalog: URL, _ sql: String) -> Int32 {
            var db: OpaquePointer?; precondition(sqlite3_open(catalog.path, &db) == SQLITE_OK)
            defer { sqlite3_close(db) }
            precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
            var statement: OpaquePointer?; precondition(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            precondition(sqlite3_step(statement) == SQLITE_ROW)
            return sqlite3_column_int(statement, 0)
        }
        let catalog = migration.root.appendingPathComponent("catalog.sqlite")
        precondition(execute(catalog, "DROP TABLE material_reclaims; DROP TABLE material_retentions; DROP TABLE material_tombstones; PRAGMA user_version=3") == 3)
        let brokenRoot = root.appendingPathComponent("broken-migration")
        try fm.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
        let brokenCatalog = brokenRoot.appendingPathComponent("catalog.sqlite")
        try fm.copyItem(at: catalog, to: brokenCatalog)
        precondition(execute(brokenCatalog, "CREATE TABLE material_tombstones(collision TEXT)") == 3)
        do { _ = try await MaterialStore(root: brokenRoot).search(); fatalError("Broken v3 migration succeeded") } catch {}
        precondition(execute(brokenCatalog, "SELECT 1") == 3)
        let migratedStore = MaterialStore(root: migration.root)
        let migratedItem = try await migratedStore.item(oldRecord.id), migratedFiles = try files(migration.root)
        precondition(migratedItem == oldItem && migratedFiles == oldFiles && execute(catalog, "SELECT 1") == 4)
        let backups = try fm.contentsOfDirectory(at: migration.root.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
        precondition(backups.count == 1 && backups[0].lastPathComponent.hasPrefix("catalog-v3-"))

        precondition(execute(pinned.root.appendingPathComponent("catalog.sqlite"), "UPDATE material_retentions SET materialID='invalid-record-id'") == 4)
        do { _ = try await durable.prepareDeletion(pinnedRecord.id); fatalError("Corrupt instrument retention ignored") } catch {}

        // Model review/dismiss/confirm has the same two-step semantics and clears stale selection.
        let modelFixture = try fixture(root.appendingPathComponent("model")), modelStore = MaterialStore(root: modelFixture.root)
        let modelRecord = try await save(modelStore, modelFixture.origin)
        try await modelStore.setTrashed(modelRecord.id, trashed: true)
        let player = PlayerModel(materialStore: modelStore), library = player.materials
        await library.reveal(modelRecord.id)
        library.reviewDeletion(protections: [], files: [])
        for _ in 0..<300 where library.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.deletionPlan != nil)
        library.dismissDeletion()
        let dismissed = try await modelStore.item(modelRecord.id); precondition(dismissed.deletedAt == nil)
        library.reviewDeletion(protections: [], files: [])
        for _ in 0..<300 where library.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        library.confirmDeletion(protections: [], files: [])
        for _ in 0..<300 where library.busy || library.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(library.error == nil && library.deletionPlan == nil && library.selected == nil && library.total == 0)
        await library.reveal(modelRecord.id)
        precondition(library.selected?.deletedAt != nil && !library.showingTrash)
        library.cancel(); player.cleanup()
        print("PASS: permanent deletion impact/capacity, shared/ancestor/instrument/reader protection, immutable tombstones/reimport, stale/cancel rejection, fail-closed archive/symlink checks, exact reclaim bytes, partial journal/restart/retry and model review")
    }
}
