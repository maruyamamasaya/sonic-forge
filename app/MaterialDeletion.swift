import Foundation
import CryptoKit

/// An open waveform or comparison keeps its managed files alive until released.
final class MaterialAudioLease: @unchecked Sendable {
    let id = UUID()
    let hashes: Set<String>
    init(_ record: MaterialRecord) { hashes = record.audioHashes }
}
final class WeakMaterialLease {
    weak var value: MaterialAudioLease?
    init(_ value: MaterialAudioLease) { self.value = value }
}
extension MaterialRecord {
    var audioHashes: Set<String> { Set([inputHash, originalHash, stemHash, clipHash]) }
}
struct MaterialProtection {
    let record: MaterialRecord
    let label: String
}
struct MaterialReclaimFile: Equatable {
    let hash: String
    let path: String
    let bytes: Int64
}
struct MaterialDeletionPlan: Identifiable {
    let id = UUID()
    let records: [MaterialRecord]
    var record: MaterialRecord { records[0] }
    let alreadyDeleted: Bool
    let files: [MaterialReclaimFile]
    let protectedFiles: Int
    let references: [String]
    let protectionIDs: Set<String>
    let witness: String
    var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
}
struct MaterialDeletionResult {
    let reclaimedBytes: Int64
    let remainingFiles: Int
}

extension MaterialStore {
    func acquireLease(_ record: MaterialRecord) -> MaterialAudioLease {
        let lease = MaterialAudioLease(record)
        readLeases[lease.id] = WeakMaterialLease(lease)
        return lease
    }
    func deletedItem(_ id: String, db: MaterialDatabase) throws -> MaterialItem {
        guard let row = try db.rows("SELECT payload,deletedAt FROM material_tombstones WHERE id=?", [id]).first,
              let seconds = Double(row[1]), seconds.isFinite else { throw AudioError.invalid("素材ライブラリに見つかりません。") }
        return MaterialItem(record: try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8)),
                            annotations: .empty, deletedAt: Date(timeIntervalSince1970: seconds))
    }
    func pendingReclaims() throws -> [MaterialItem] {
        let db = try database()
        return try db.rows("SELECT DISTINCT materialID FROM material_reclaims ORDER BY materialID").map { try deletedItem($0[0], db: db) }
    }
    /// Conservative durable retention: removing a library entry does not silently revoke this protection.
    func retain(_ protections: [MaterialProtection]) throws {
        guard !protections.isEmpty, FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.sqlite").path) else { return }
        let db = try database()
        try db.execute("BEGIN IMMEDIATE")
        do {
            for protection in protections {
                let r = protection.record
                try InstrumentProvenance(material: r, startFrame: r.startFrame, endFrame: r.endFrame)
                    .validate(frames: r.selection.frameCount, sampleRate: r.provenance.sampleRate)
                let existing = try db.rows("SELECT payload FROM materials WHERE id=? UNION ALL SELECT payload FROM material_tombstones WHERE id=?", [r.id, r.id])
                if let row = existing.first {
                    guard try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8)) == r else {
                        throw AudioError.invalid("楽器と素材の来歴が一致しないため、音声回収を停止しました。")
                    }
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                try db.execute("INSERT OR IGNORE INTO material_retentions VALUES(?,?,?)", [r.id, String(protection.label.prefix(255)), String(decoding: try encoder.encode(r), as: UTF8.self)])
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    /// Read metadata without decoding embedded PCM. Unknown/unreadable registered files fail closed.
    private func audit(_ urls: [URL]) throws -> [MaterialProtection] {
        struct Instrument: Decodable { let version: Int; let provenance: InstrumentProvenance? }
        struct Part: Decodable { let instrument: Instrument }
        struct Song: Decodable { let version: Int; let parts: [Part] }
        var result: [MaterialProtection] = []
        for url in Set(urls).sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let song = url.pathExtension.lowercased() == "sfensemble"
                guard size > 0, size <= (song ? 384 : 96) * 1024 * 1024 else { throw AudioError.invalid("ファイル容量が無効です。") }
                let data = try Data(contentsOf: url)
                let instruments: [Instrument]
                if song {
                    let archive = try JSONDecoder().decode(Song.self, from: data)
                    guard (1...12).contains(archive.version), (1...4).contains(archive.parts.count) else { throw AudioError.invalid("構成の版が無効です。") }
                    instruments = archive.parts.map(\.instrument)
                } else { instruments = [try JSONDecoder().decode(Instrument.self, from: data)] }
                for instrument in instruments {
                    guard (1...5).contains(instrument.version), (instrument.version == 5) == (instrument.provenance != nil) else { throw AudioError.invalid("楽器の版と来歴を確認できません。") }
                    if let p = instrument.provenance { result.append(MaterialProtection(record: p.material, label: "保存ファイル: " + url.lastPathComponent)) }
                }
            } catch { throw AudioError.invalid(url.lastPathComponent + "の来歴を確認できないため、削除していません。登録やファイルを確認してください。") }
        }
        return result
    }
    func prepareDeletion(_ id: String, protections: [MaterialProtection] = [], files: [URL] = []) throws -> MaterialDeletionPlan {
        guard !hasPendingMaterial else { throw AudioError.invalid("素材の保存準備を完了または破棄してから削除してください。") }
        let audited = try audit(files)
        try retain(protections + audited)
        return try deletionPlan(id, db: database())
    }
    func prepareBatchDeletion(_ ids: Set<String>, protections: [MaterialProtection] = [], files: [URL] = []) throws -> MaterialDeletionPlan {
        guard !hasPendingMaterial else { throw AudioError.invalid("素材の保存準備を完了または破棄してから削除してください。") }
        guard !ids.isEmpty, ids.count <= 50 else { throw AudioError.invalid("ゴミ箱から1〜50件を選択してください。") }
        for id in ids { guard try item(id).trashedAt != nil else { throw AudioError.invalid("選択にゴミ箱以外の素材があります。一覧を確認してください。") } }
        try retain(protections + audit(files))
        return try deletionPlan(ids: ids, db: database())
    }
    private func deletionPlan(_ id: String, db: MaterialDatabase, inspecting: Bool = false) throws -> MaterialDeletionPlan {
        try deletionPlan(ids: [id], db: db, inspecting: inspecting)
    }
    private func deletionPlan(ids: Set<String>, db: MaterialDatabase, inspecting: Bool = false) throws -> MaterialDeletionPlan {
        guard !hasPendingMaterial else { throw AudioError.invalid("素材の保存準備が変わりました。もう一度影響を確認してください。") }
        guard !ids.isEmpty, ids.count <= 50 else { throw AudioError.invalid("削除対象の件数が無効です。") }
        let items = try ids.sorted().map { try item($0) }
        guard inspecting || items.allSatisfy({ $0.trashedAt != nil || (ids.count == 1 && $0.deletedAt != nil) }) else {
            throw AudioError.invalid("ゴミ箱の素材だけを完全削除できます。")
        }
        let decoder = JSONDecoder()
        let activeRows = try db.rows("SELECT id,payload FROM materials ORDER BY id")
        let deadRows = try db.rows("SELECT id,payload FROM material_tombstones ORDER BY id")
        func records(_ rows: [[String]]) throws -> [MaterialRecord] {
            try rows.map { row in
                let record = try decoder.decode(MaterialRecord.self, from: Data(row[1].utf8))
                guard record.id == row[0] else { throw AudioError.invalid("素材の識別情報が一致しません。回収を停止しました。") }
                return record
            }
        }
        let active = try records(activeRows), dead = try records(deadRows)
        var all: [String: MaterialRecord] = [:]
        for r in active + dead {
            guard all.updateValue(r, forKey: r.id) == nil, r.audioHashes.allSatisfy(MaterialHash.valid) else { throw AudioError.invalid("来歴の識別情報が不正なため回収を停止しました。") }
        }
        func ancestors(_ r: MaterialRecord) throws -> [MaterialRecord] {
            var records = [r], seen: Set<String> = [r.id], parent = r.parentMaterialID
            while let id = parent {
                guard seen.insert(id).inserted, let next = all[id] else { throw AudioError.invalid("親素材の来歴を確認できないため回収を停止しました。") }
                records.append(next); parent = next.parentMaterialID
            }
            return records
        }
        // The candidate pool is this material and its already-deleted ancestors, never unrelated orphan files.
        let deadIDs = Set(dead.map(\.id))
        let pool = try items.flatMap { try ancestors($0.record) }.filter { ids.contains($0.id) || deadIDs.contains($0.id) }
        var hashes = Set(pool.flatMap { $0.audioHashes })
        for id in ids {
            let queued = try db.rows("SELECT hash FROM material_reclaims WHERE materialID=?", [id])
            hashes.formUnion(queued.map { $0[0] })
        }
        var protected = Set<String>(), references = Set<String>(), protectionIDs = Set<String>()
        for r in active where !ids.contains(r.id) || inspecting {
            let lineage = try ancestors(r)
            let retained = Set(lineage.flatMap { $0.audioHashes })
            protected.formUnion(retained)
            if !retained.isDisjoint(with: hashes) { references.insert("素材: " + r.name) }
        }
        let pins = try db.rows("SELECT materialID,label,payload FROM material_retentions ORDER BY materialID,label")
        for row in pins {
            let r = try decoder.decode(MaterialRecord.self, from: Data(row[2].utf8))
            guard r.id == row[0], r.audioHashes.allSatisfy(MaterialHash.valid), all[r.id].map({ $0 == r }) ?? true else {
                throw AudioError.invalid("楽器の保護記録と来歴が一致しないため回収を停止しました。")
            }
            let lineage = all[r.id] == nil ? [r] : try ancestors(r)
            let retained = Set(lineage.flatMap { $0.audioHashes })
            protected.formUnion(retained)
            if !retained.isDisjoint(with: hashes) { references.insert(row[1]); protectionIDs.insert(row[0] + "\n" + row[1]) }
        }
        readLeases = readLeases.filter { $0.value.value != nil }
        var leases: [String] = []
        for (id, weak) in readLeases {
            if let lease = weak.value {
                protected.formUnion(lease.hashes); leases.append(id.uuidString)
                if !lease.hashes.isDisjoint(with: hashes) { references.insert("開いている波形・試聴（音声を保持）") }
            }
        }
        var candidates: [MaterialReclaimFile] = []
        for hash in hashes.subtracting(protected).sorted() {
            guard let row = try db.rows("SELECT path,bytes FROM blobs WHERE hash=?", [hash]).first, let bytes = Int64(row[1]) else { throw AudioError.invalid("回収する音声情報が無効です。") }
            let file = MaterialReclaimFile(hash: hash, path: row[0], bytes: bytes)
            if try checkedReclaimURL(file) != nil { candidates.append(file) }
        }
        let tables = ["blobs", "materials", "material_trash", "material_annotations", "material_tags", "material_tombstones", "material_retentions", "material_reclaims"]
        var state = [[String]]()
        for table in tables { state.append(contentsOf: try db.rows("SELECT * FROM " + table + " ORDER BY 1,2")) }
        state.append(ids.sorted()); state.append(leases.sorted()); state.append(candidates.map { $0.hash + ":" + String($0.bytes) })
        let digest = SHA256.hash(data: try JSONEncoder().encode(state)).map { String(format: "%02x", $0) }.joined()
        return MaterialDeletionPlan(records: items.map(\.record), alreadyDeleted: items.allSatisfy { $0.deletedAt != nil }, files: candidates,
            protectedFiles: hashes.intersection(protected).count, references: references.sorted(), protectionIDs: protectionIDs, witness: digest)
    }
    struct ProtectionEntry: Identifiable {
        let materialID: String
        let label: String
        var id: String { materialID + "\n" + label }
    }
    struct ProtectionReview: Identifiable {
        let id = UUID()
        let materialID: String
        let references: [String]
        let entries: [ProtectionEntry]
    }
    struct ReleasePlan: Identifiable {
        let id = UUID()
        let entry: ProtectionEntry
        let materialID: String
        let before: MaterialDeletionPlan
        let after: MaterialDeletionPlan
        let blocked: Bool
    }
    func protectedDeletedItems() throws -> [MaterialItem] {
        let db = try database()
        return try db.rows("SELECT id FROM material_tombstones ORDER BY id")
            .map { try deletedItem($0[0], db: db) }
    }
    func protectionReview(_ id: String, protections: [MaterialProtection], files: [URL]) throws -> ProtectionReview {
        try retain(protections + audit(files))
        let db = try database(), plan = try deletionPlan(id, db: db, inspecting: true)
        // Include pins sharing audio or ancestral records, rather than only this material's ID.
        let entries = try db.rows("SELECT materialID,label FROM material_retentions ORDER BY materialID,label")
            .filter { plan.protectionIDs.contains($0[0] + "\n" + $0[1]) }
            .map { ProtectionEntry(materialID: $0[0], label: $0[1]) }
        return ProtectionReview(materialID: id, references: plan.references, entries: entries)
    }
    func prepareRelease(_ entry: ProtectionEntry, materialID: String, protections: [MaterialProtection], files: [URL]) throws -> ReleasePlan {
        let current = protections + (try audit(files))
        try retain(current)
        let db = try database()
        let before = try deletionPlan(materialID, db: db, inspecting: true)
        guard try !db.rows("SELECT payload FROM material_retentions WHERE materialID=? AND label=?", [entry.materialID, entry.label]).isEmpty else {
            throw AudioError.invalid("保護記録が変わりました。一覧を開き直してください。")
        }
        let blocked = current.contains { $0.record.id == entry.materialID && $0.label == entry.label }
        try db.execute("BEGIN IMMEDIATE")
        do {
            try db.execute("DELETE FROM material_retentions WHERE materialID=? AND label=?", [entry.materialID, entry.label])
            let after = try deletionPlan(materialID, db: db, inspecting: true)
            try db.execute("ROLLBACK")
            return ReleasePlan(entry: entry, materialID: materialID, before: before, after: after, blocked: blocked)
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    func releaseProtection(_ plan: ReleasePlan, protections: [MaterialProtection], files: [URL]) throws {
        let current = try prepareRelease(plan.entry, materialID: plan.materialID, protections: protections, files: files)
        guard !current.blocked, current.before.witness == plan.before.witness,
              current.after.files == plan.after.files else {
            throw AudioError.invalid("使用中の参照または保護状態が変わりました。解除せず、一覧を確認してください。")
        }
        let db = try database()
        try db.execute("BEGIN IMMEDIATE")
        do {
            let latest = try deletionPlan(plan.materialID, db: db, inspecting: true)
            guard latest.witness == current.before.witness else { throw AudioError.invalid("保護状態が変わりました。再確認してください。") }
            try Task.checkCancellation()
            try db.execute("DELETE FROM material_retentions WHERE materialID=? AND label=?", [plan.entry.materialID, plan.entry.label])
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    private func checkedReclaimURL(_ file: MaterialReclaimFile) throws -> URL? {
        let expected = "objects/\(file.hash.prefix(2))/\(file.hash)."
        guard MaterialHash.valid(file.hash), [expected + "wav", expected + "mp3"].contains(file.path), file.bytes > 0 else {
            throw AudioError.invalid("管理音声の場所が不正なため回収しません。")
        }
        let base = root.resolvingSymlinksInPath(), url = base.appendingPathComponent(file.path)
        guard url.resolvingSymlinksInPath() == url else { throw AudioError.invalid("管理音声にシンボリックリンクがあるため回収しません。") }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == file.bytes,
              try MaterialHash.file(url) == file.hash else { throw AudioError.invalid("管理音声が変わっているため回収しません。") }
        return url
    }
    func deletePermanently(_ plan: MaterialDeletionPlan, protections: [MaterialProtection] = [], files: [URL] = []) throws -> MaterialDeletionResult {
        let audited = try audit(files)
        try retain(protections + audited)
        let db = try database()
        try db.execute("BEGIN IMMEDIATE")
        do {
            let current = try deletionPlan(ids: Set(plan.records.map(\.id)), db: db)
            guard current.witness == plan.witness, current.files == plan.files else { throw AudioError.invalid("参照や音声が変わりました。削除せず、もう一度影響を確認してください。") }
            try Task.checkCancellation()
            for record in plan.records where !plan.alreadyDeleted {
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                try db.execute("INSERT INTO material_tombstones VALUES(?,?,?)", [record.id, String(decoding: try encoder.encode(record), as: UTF8.self), String(Date().timeIntervalSince1970)])
                try db.execute("DELETE FROM material_tags WHERE materialID=?", [record.id])
                try db.execute("DELETE FROM material_annotations WHERE materialID=?", [record.id])
                try db.execute("DELETE FROM material_trash WHERE materialID=?", [record.id])
                try db.execute("DELETE FROM materials WHERE id=?", [record.id])
            }
            // Persist the approved work before unlinking. A crash leaves a retryable journal.
            for record in plan.records {
                try db.execute("DELETE FROM material_reclaims WHERE materialID=?", [record.id])
            }
            for file in plan.files {
                try db.execute("INSERT OR REPLACE INTO material_reclaims VALUES(?,?,?,?)", [file.hash, plan.record.id, file.path, String(file.bytes)])
            }
            try Task.checkCancellation()
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
        var bytes: Int64 = 0
        // After commit this operation is successful deletion, even if cancellation or unlink fails.
        for file in plan.files {
            do {
                if let url = try checkedReclaimURL(file) { try reclaimFile(url); bytes += file.bytes }
                try db.execute("DELETE FROM material_reclaims WHERE hash=? AND materialID=?", [file.hash, plan.record.id])
            } catch { /* Keep journal and audio for explicit review/retry. */ }
        }
        return MaterialDeletionResult(reclaimedBytes: bytes, remainingFiles: try db.rows("SELECT hash FROM material_reclaims WHERE materialID=?", [plan.record.id]).count)
    }
}
