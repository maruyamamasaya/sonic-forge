import Foundation
import AVFoundation
import SQLite3

struct MaterialRecord: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let created: Date
    let provenance: MaterialProvenance
    let startFrame: Int64
    let endFrame: Int64
    let inputHash: String
    let inputFormat: String
    let originalHash: String
    let stemHash: String
    let clipHash: String
    var parentMaterialID: String? = nil
    var selection: AudioSelection { AudioSelection(startFrame: startFrame, endFrame: endFrame) }
    var location: String {
        String(format: "%.3f–%.3f 秒 · %@", Double(startFrame) / provenance.sampleRate,
               Double(endFrame) / provenance.sampleRate, provenance.stem)
    }
}
struct MaterialAnnotations: Equatable {
    let tags: [String]
    let note: String
    static let empty = MaterialAnnotations(tags: [], note: "")
}
struct MaterialItem: Identifiable, Equatable {
    let record: MaterialRecord
    let annotations: MaterialAnnotations
    var trashedAt: Date? = nil
    var deletedAt: Date? = nil
    var id: String { record.id }
}
struct MaterialPage {
    let items: [MaterialItem]
    let total: Int
}
struct MaterialTag: Identifiable {
    let id: String
    let name: String
}

struct MaterialDraft: Identifiable {
    let id: UUID
    let record: MaterialRecord
    let additionalBytes: Int64
    let workingBytes: Int64
}
struct MaterialRestoration {
    let record: MaterialRecord
    let origin: MaterialOrigin
    let clip: URL
}

/// Connections and file publication are confined to this actor; no audio on MainActor.
actor MaterialStore {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SonicForge/Materials", isDirectory: true)
    }
    let root: URL
    private struct Blob {
        let hash: String
        let format: String
        let size: Int64
        let staged: URL
        var relative: String { "objects/\(hash.prefix(2))/\(hash).\(format)" }
    }
    private struct Pending { let draft: MaterialDraft; let directory: URL; let blobs: [Blob] }
    private var pending: [UUID: Pending] = [:]
    private var initialized = false
    var readLeases: [UUID: WeakMaterialLease] = [:]
    let reclaimFile: @Sendable (URL) throws -> Void
    var hasPendingMaterial: Bool { !pending.isEmpty }
    init(root: URL = MaterialStore.defaultRoot, reclaimFile: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.root = root; self.reclaimFile = reclaimFile
    }

    func database() throws -> MaterialDatabase {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try MaterialDatabase(root.appendingPathComponent("catalog.sqlite"))
        let version = try db.rows("PRAGMA user_version").first?.first ?? "0"
        guard ["0", "1", "2", "3", "4"].contains(version) else { throw AudioError.invalid("素材DBの版に対応していません。データは保持しています。") }
        if version == "0" {
            // DDL is transactional. An existing corrupt/nonempty DB is never reset.
            guard try db.rows("SELECT name FROM sqlite_master WHERE type='table'").isEmpty else {
                throw AudioError.invalid("素材DBの構造を確認できません。データは保持しています。")
            }
            try db.execute("BEGIN IMMEDIATE")
            do {
                try db.execute("CREATE TABLE blobs(hash TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, bytes INTEGER NOT NULL)")
                try db.execute("CREATE TABLE sources(id TEXT PRIMARY KEY, inputHash TEXT NOT NULL UNIQUE REFERENCES blobs(hash))")
                try db.execute("CREATE TABLE runs(id TEXT PRIMARY KEY, sourceID TEXT NOT NULL REFERENCES sources(id), originalHash TEXT NOT NULL REFERENCES blobs(hash), metadata TEXT NOT NULL)")
                try db.execute("CREATE TABLE stems(id TEXT PRIMARY KEY, runID TEXT NOT NULL REFERENCES runs(id), kind TEXT NOT NULL, hash TEXT NOT NULL REFERENCES blobs(hash), UNIQUE(runID,kind))")
                try db.execute("CREATE TABLE materials(id TEXT PRIMARY KEY, stemID TEXT NOT NULL REFERENCES stems(id), start INTEGER NOT NULL, end INTEGER NOT NULL, name TEXT NOT NULL, created REAL NOT NULL, clipHash TEXT NOT NULL REFERENCES blobs(hash), payload TEXT NOT NULL, UNIQUE(stemID,start,end))")
                try db.execute("PRAGMA user_version=1")
                try db.execute("COMMIT")
            } catch { try? db.execute("ROLLBACK"); throw error }
        }
        if version == "0" || version == "1" {
            if version == "1" {
                let backups = root.appendingPathComponent("backups")
                try manager.createDirectory(at: backups, withIntermediateDirectories: true)
                try db.backup(to: backups.appendingPathComponent("catalog-v1-" + UUID().uuidString + ".sqlite"))
            }
            try db.execute("BEGIN IMMEDIATE")
            do {
                try db.execute("CREATE TABLE material_annotations(materialID TEXT PRIMARY KEY REFERENCES materials(id), note TEXT NOT NULL, searchKey TEXT NOT NULL)")
                try db.execute("CREATE TABLE tags(id TEXT PRIMARY KEY, name TEXT NOT NULL, searchKey TEXT NOT NULL UNIQUE)")
                try db.execute("CREATE TABLE material_tags(materialID TEXT NOT NULL REFERENCES materials(id), tagID TEXT NOT NULL REFERENCES tags(id), PRIMARY KEY(materialID,tagID))")
                for row in try db.rows("SELECT id,payload FROM materials") {
                    try Task.checkCancellation()
                    let r = try JSONDecoder().decode(MaterialRecord.self, from: Data(row[1].utf8))
                    guard row[0] == r.id else { throw AudioError.invalid("素材の識別情報が一致しません。") }
                    try db.execute("INSERT INTO material_annotations VALUES(?,?,?)", [r.id, "", Self.searchKey(r, .empty)])
                }
                try db.execute("PRAGMA user_version=2")
                try db.execute("COMMIT")
            } catch { try? db.execute("ROLLBACK"); throw error }
        }
        if ["0", "1", "2"].contains(version) {
            if version == "2" {
                let backups = root.appendingPathComponent("backups")
                try manager.createDirectory(at: backups, withIntermediateDirectories: true)
                try db.backup(to: backups.appendingPathComponent("catalog-v2-" + UUID().uuidString + ".sqlite"))
            }
            try db.execute("BEGIN IMMEDIATE")
            do {
                try db.execute("CREATE TABLE material_trash(materialID TEXT PRIMARY KEY REFERENCES materials(id), trashedAt REAL NOT NULL)")
                try Task.checkCancellation()
                try db.execute("PRAGMA user_version=3")
                try db.execute("COMMIT")
            } catch { try? db.execute("ROLLBACK"); throw error }
        }
        if version != "4" {
            if version == "3" {
                let backups = root.appendingPathComponent("backups")
                try manager.createDirectory(at: backups, withIntermediateDirectories: true)
                try db.backup(to: backups.appendingPathComponent("catalog-v3-" + UUID().uuidString + ".sqlite"))
            }
            try db.execute("BEGIN IMMEDIATE")
            do {
                try db.execute("CREATE TABLE material_tombstones(id TEXT PRIMARY KEY, payload TEXT NOT NULL, deletedAt REAL NOT NULL)")
                try db.execute("CREATE TABLE material_retentions(materialID TEXT NOT NULL, label TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(materialID,label))")
                try db.execute("CREATE TABLE material_reclaims(hash TEXT PRIMARY KEY REFERENCES blobs(hash), materialID TEXT NOT NULL, path TEXT NOT NULL, bytes INTEGER NOT NULL)")
                try Task.checkCancellation()
                try db.execute("PRAGMA user_version=4")
                try db.execute("COMMIT")
            } catch { try? db.execute("ROLLBACK"); throw error }
        }
        if !initialized {
            // Single local writer. Only abandoned staging is disposable; objects are preserved.
            let staging = root.appendingPathComponent("staging")
            if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            initialized = true
        }
        return db
    }

    func list() throws -> [MaterialRecord] {
        let db = try database()
        return try db.rows("SELECT payload FROM materials WHERE NOT EXISTS(SELECT 1 FROM material_trash WHERE materialID=materials.id) ORDER BY created DESC, id DESC").map {
            try JSONDecoder().decode(MaterialRecord.self, from: Data($0[0].utf8))
        }
    }

    static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func searchKey(_ record: MaterialRecord, _ annotations: MaterialAnnotations) -> String {
        normalize(([record.name, record.provenance.sourceName, annotations.note] + annotations.tags).joined(separator: "\n"))
    }
    private func annotations(_ id: String, db: MaterialDatabase) throws -> MaterialAnnotations {
        guard let row = try db.rows("SELECT note FROM material_annotations WHERE materialID=?", [id]).first else { throw AudioError.invalid("素材の注釈が見つかりません。") }
        let tags = try db.rows("SELECT t.name FROM tags t JOIN material_tags mt ON mt.tagID=t.id WHERE mt.materialID=? ORDER BY t.searchKey,t.id", [id]).map { $0[0] }
        return MaterialAnnotations(tags: tags, note: row[0])
    }
    func tags(trashed: Bool = false) throws -> [MaterialTag] {
        let db = try database()
        return try db.rows("SELECT t.id,t.name FROM tags t WHERE EXISTS(SELECT 1 FROM material_tags mt WHERE mt.tagID=t.id AND \(trashed ? "" : "NOT ")EXISTS(SELECT 1 FROM material_trash x WHERE x.materialID=mt.materialID)) ORDER BY t.searchKey,t.id").map { MaterialTag(id: $0[0], name: $0[1]) }
    }
    func search(query: String = "", tagID: String? = nil, offset: Int = 0, limit: Int = 50, trashed: Bool = false) throws -> MaterialPage {
        guard query.count <= 300, !query.contains("\0"), offset >= 0, (1...50).contains(limit) else { throw AudioError.invalid("検索条件が長すぎるか、表示範囲が無効です。") }
        let db = try database()
        let terms = Self.normalize(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard terms.count <= 12 else { throw AudioError.invalid("検索語は12個以内にしてください。") }
        var conditions: [String] = ["\(trashed ? "" : "NOT ")EXISTS(SELECT 1 FROM material_trash x WHERE x.materialID=m.id)"], args: [String] = []
        for term in terms {
            conditions.append("a.searchKey LIKE ? ESCAPE '\\'")
            let escaped = term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            args.append("%" + escaped + "%")
        }
        if let tagID {
            conditions.append("EXISTS(SELECT 1 FROM material_tags mt WHERE mt.materialID=m.id AND mt.tagID=?)")
            args.append(tagID)
        }
        let filter = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        let from = " FROM materials m JOIN material_annotations a ON a.materialID=m.id" + filter
        let total = Int(try db.rows("SELECT count(*)" + from, args)[0][0]) ?? 0
        let rows = try db.rows("SELECT m.payload" + from + " ORDER BY m.created DESC,m.id DESC LIMIT ? OFFSET ?", args + [String(limit), String(offset)])
        let items = try rows.map { row -> MaterialItem in
            try Task.checkCancellation()
            let record = try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8))
            return MaterialItem(record: record, annotations: try annotations(record.id, db: db), trashedAt: try trashDate(record.id, db: db))
        }
        return MaterialPage(items: items, total: total)
    }
    func item(_ id: String) throws -> MaterialItem {
        let db = try database()
        guard let row = try db.rows("SELECT payload FROM materials WHERE id=?", [id]).first else { return try deletedItem(id, db: db) }
        let record = try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8))
        return MaterialItem(record: record, annotations: try annotations(id, db: db), trashedAt: try trashDate(id, db: db))
    }
    private func trashDate(_ id: String, db: MaterialDatabase) throws -> Date? {
        guard let row = try db.rows("SELECT trashedAt FROM material_trash WHERE materialID=?", [id]).first else { return nil }
        guard let seconds = Double(row[0]), seconds.isFinite else { throw AudioError.invalid("ゴミ箱の日時が無効です。") }
        return Date(timeIntervalSince1970: seconds)
    }
    /// Only visibility changes. Never remove records, ancestry or shared audio.
    func setTrashed(_ id: String, trashed: Bool) throws {
        let db = try database()
        try Task.checkCancellation()
        try db.execute("BEGIN IMMEDIATE")
        do {
            guard !(try db.rows("SELECT id FROM materials WHERE id=?", [id])).isEmpty else {
                throw AudioError.invalid("素材が見つかりません。")
            }
            if trashed {
                try db.execute("INSERT OR IGNORE INTO material_trash VALUES(?,?)", [id, String(Date().timeIntervalSince1970)])
            } else { try db.execute("DELETE FROM material_trash WHERE materialID=?", [id]) }
            try Task.checkCancellation()
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    func updateAnnotations(_ id: String, tags: [String], note: String) throws -> MaterialAnnotations {
        guard tags.count <= 20, note.count <= 4000, !note.contains("\0"), !tags.contains(where: { $0.contains("\0") }) else { throw AudioError.invalid("タグは20個、メモは4000文字以内にしてください。") }
        var seen = Set<String>()
        let cleaned = try tags.compactMap { raw -> String? in
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return nil }
            guard tag.count <= 40, tag.rangeOfCharacter(from: CharacterSet(charactersIn: ",，、\n\r")) == nil else { throw AudioError.invalid("タグは1個40文字以内で、区切り文字・改行を含めず入力してください。") }
            return seen.insert(Self.normalize(tag)).inserted ? tag : nil
        }
        let db = try database()
        guard let row = try db.rows("SELECT payload FROM materials WHERE id=?", [id]).first else { throw AudioError.invalid("素材が見つかりません。") }
        let record = try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8))
        try Task.checkCancellation()
        try db.execute("BEGIN IMMEDIATE")
        do {
            try db.execute("DELETE FROM material_tags WHERE materialID=?", [id])
            for tag in cleaned {
                try db.execute("INSERT OR IGNORE INTO tags VALUES(?,?,?)", [UUID().uuidString, tag, Self.normalize(tag)])
                let tagID = try db.rows("SELECT id FROM tags WHERE searchKey=?", [Self.normalize(tag)])[0][0]
                try db.execute("INSERT INTO material_tags VALUES(?,?)", [id, tagID])
            }
            let actual = try annotations(id, db: db)
            let next = MaterialAnnotations(tags: actual.tags, note: note)
            try db.execute("UPDATE material_annotations SET note=?,searchKey=? WHERE materialID=?", [note, Self.searchKey(record, next), id])
            try Task.checkCancellation()
            try db.execute("COMMIT")
            return next
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    func prepare(origin: MaterialOrigin, selection localSelection: AudioSelection, name: String) throws -> MaterialDraft {
        let db = try database()
        let p = origin.provenance
        let selection = try origin.absolute(localSelection)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 160,
              MaterialHash.valid(p.inputSHA256), MaterialHash.valid(p.weightSHA256),
              p.model == "htdemucs", p.backend == "mlx-metal", p.settings == .standard, !p.runID.isEmpty, p.runID.count <= 100,
              ["drums", "bass", "other", "vocals"].contains(p.stem),
              p.sampleRate == 44100, p.frames > 1, p.frames <= 600 * 44100,
              p.gain.isFinite, p.gain > 0, p.gain <= 1,
              selection.startFrame >= 0, selection.endFrame <= p.frames, selection.frameCount > 0,
              selection.frameCount <= 30 * 44100 else {
            throw AudioError.invalid("名前と30秒以内の有効な分離音の範囲を指定してください。")
        }
        let id = UUID(), directory = root.appendingPathComponent("staging/" + id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: directory) } }
        let inputFormat = origin.input.pathExtension.lowercased()
        guard ["wav", "mp3"].contains(inputFormat) else { throw AudioError.invalid("元曲の形式が無効です。") }
        let inputs = [(origin.input, inputFormat), (origin.original, "wav"), (origin.stem, "wav")]
        let sizes = try inputs.map { try $0.0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
        guard sizes.allSatisfy({ $0 > 0 && $0 <= 256 * 1024 * 1024 }) else { throw AudioError.invalid("音声ファイルの容量が無効です。") }
        let working = Int64(sizes.reduce(0, +)) + selection.frameCount * 8 + 4096
        let free = try FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber
        guard (free?.int64Value ?? 0) > working + 16 * 1024 * 1024 else { throw AudioError.invalid("素材を保存する空き容量が不足しています。") }
        var blobs: [Blob] = []
        for (index, pair) in inputs.enumerated() {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent("\(index).\(pair.1)")
            try FileManager.default.copyItem(at: pair.0, to: destination)
            if index > 0 { try Self.validateAudio(destination, frames: p.frames) }
            blobs.append(Blob(hash: try MaterialHash.file(destination), format: pair.1,
                              size: Int64(sizes[index]), staged: destination))
        }
        guard blobs[0].hash == p.inputSHA256 else { throw AudioError.invalid("元曲の内容が分離時から変わっています。") }
        let clip = directory.appendingPathComponent("clip.wav")
        try WAVExport.write(source: blobs[2].staged, selection: selection, to: clip)
        try Self.validateAudio(clip, frames: selection.frameCount)
        blobs.append(Blob(hash: try MaterialHash.file(clip), format: "wav",
                          size: Int64(try clip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), staged: clip))
        var unique = Set<String>(), additional: Int64 = 0
        for blob in blobs where unique.insert(blob.hash).inserted {
            if try db.rows("SELECT hash FROM blobs WHERE hash=?", [blob.hash]).isEmpty { additional += blob.size }
        }
        let record = MaterialRecord(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines), created: Date(),
            provenance: p, startFrame: selection.startFrame, endFrame: selection.endFrame,
            inputHash: blobs[0].hash, inputFormat: inputFormat, originalHash: blobs[1].hash, stemHash: blobs[2].hash, clipHash: blobs[3].hash, parentMaterialID: origin.record?.id)
        let draft = MaterialDraft(id: id, record: record, additionalBytes: additional, workingBytes: working)
        pending[id] = Pending(draft: draft, directory: directory, blobs: blobs)
        retained = true
        return draft
    }

    func discard(_ id: UUID) {
        if let value = pending.removeValue(forKey: id) { try? FileManager.default.removeItem(at: value.directory) }
    }

    func commit(_ id: UUID) throws -> MaterialRecord {
        guard let value = pending[id] else { throw AudioError.invalid("保存準備が見つかりません。もう一度準備してください。") }
        defer { discard(id) }
        let db = try database(), r = value.draft.record
        try Task.checkCancellation()
        // Revalidate staged data immediately before publication; committed rows only reference complete objects.
        for blob in value.blobs {
            guard try MaterialHash.file(blob.staged) == blob.hash else { throw AudioError.invalid("保存準備中の音声が変わっています。") }
            let target = root.appendingPathComponent(blob.relative)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                guard try MaterialHash.file(target) == blob.hash else { throw AudioError.invalid("管理音声が破損しています。既存データは保持しています。") }
            } else { try FileManager.default.moveItem(at: blob.staged, to: target) }
        }
        try Task.checkCancellation()
        try db.execute("BEGIN IMMEDIATE")
        do {
            for blob in value.blobs { try db.execute("INSERT OR IGNORE INTO blobs VALUES(?,?,?)", [blob.hash, blob.relative, String(blob.size)]) }
            try db.execute("INSERT OR IGNORE INTO sources VALUES(?,?)", [UUID().uuidString, r.inputHash])
            let sourceID = try db.rows("SELECT id FROM sources WHERE inputHash=?", [r.inputHash])[0][0]
            let metadata = try Self.json(r.provenance)
            // A run ID must never silently change its source, processing settings or stem bytes.
            let runs = try db.rows("SELECT sourceID,originalHash,metadata FROM runs WHERE id=?", [r.provenance.runID])
            if let old = runs.first {
                guard var prior = try JSONSerialization.jsonObject(with: Data(old[2].utf8)) as? [String: Any],
                      var next = try JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any] else {
                    throw AudioError.invalid("分離条件の保存情報が無効です。")
                }
                prior.removeValue(forKey: "stem"); next.removeValue(forKey: "stem")
                guard old[0] == sourceID, old[1] == r.originalHash,
                      NSDictionary(dictionary: prior).isEqual(to: next) else { throw AudioError.invalid("同じ分離IDの来歴が一致しません。") }
            } else { try db.execute("INSERT INTO runs VALUES(?,?,?,?)", [r.provenance.runID, sourceID, r.originalHash, metadata]) }
            try db.execute("INSERT OR IGNORE INTO stems VALUES(?,?,?,?)", [UUID().uuidString, r.provenance.runID, r.provenance.stem, r.stemHash])
            let stem = try db.rows("SELECT id,hash FROM stems WHERE runID=? AND kind=?", [r.provenance.runID, r.provenance.stem])[0]
            guard stem[1] == r.stemHash else { throw AudioError.invalid("分離パートの内容が一致しません。") }
            let existing = try db.rows("SELECT payload FROM materials WHERE stemID=? AND start=? AND end=?", [stem[0], String(r.startFrame), String(r.endFrame)])
            let result: MaterialRecord
            if let old = existing.first {
                result = try JSONDecoder().decode(MaterialRecord.self, from: Data(old[0].utf8))
                guard try trashDate(result.id, db: db) == nil else {
                    throw AudioError.invalid("同じ区間の素材がゴミ箱にあります。ゴミ箱から復元してください。")
                }
            }
            else {
                var inherited = MaterialAnnotations.empty
                if let parentID = r.parentMaterialID {
                    guard parentID != r.id,
                          let row = try db.rows("SELECT payload FROM materials WHERE id=? UNION ALL SELECT payload FROM material_tombstones WHERE id=?", [parentID, parentID]).first else {
                        throw AudioError.invalid("親素材が見つかりません。")
                    }
                    let parent = try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8))
                    guard parent.provenance == r.provenance, parent.inputHash == r.inputHash,
                          parent.originalHash == r.originalHash, parent.stemHash == r.stemHash else {
                        throw AudioError.invalid("親素材と元曲の来歴が一致しません。")
                    }
                    if !(try db.rows("SELECT id FROM materials WHERE id=?", [parentID])).isEmpty { inherited = try annotations(parentID, db: db) }
                }
                try db.execute("INSERT INTO materials VALUES(?,?,?,?,?,?,?,?)", [r.id, stem[0], String(r.startFrame), String(r.endFrame), r.name, String(r.created.timeIntervalSince1970), r.clipHash, try Self.json(r)])
                try db.execute("INSERT INTO material_annotations VALUES(?,?,?)", [r.id, inherited.note, Self.searchKey(r, inherited)])
                if let parentID = r.parentMaterialID {
                    try db.execute("INSERT INTO material_tags SELECT ?,tagID FROM material_tags WHERE materialID=?", [r.id, parentID])
                }
                result = r
            }
            try db.execute("COMMIT")
            // Commit is the point of success. Do not report cancellation afterwards.
            return result
        } catch { try? db.execute("ROLLBACK"); throw error }
    }

    func restore(_ id: String, includeDeleted: Bool = false) throws -> MaterialRestoration {
        let db = try database()
        let rows = try db.rows(includeDeleted ? "SELECT payload FROM materials WHERE id=? UNION ALL SELECT payload FROM material_tombstones WHERE id=?" : "SELECT payload FROM materials WHERE id=?", includeDeleted ? [id, id] : [id])
        guard let row = rows.first else { throw AudioError.invalid("素材は完全削除されたか、見つかりません。来歴は参照記録で確認できます。") }
        let r = try JSONDecoder().decode(MaterialRecord.self, from: Data(row[0].utf8))
        guard r.id == id, r.startFrame >= 0, r.endFrame <= r.provenance.frames,
              r.endFrame > r.startFrame, r.endFrame - r.startFrame <= 30 * 44100,
              r.provenance.frames <= 600 * 44100, r.provenance.sampleRate == 44100,
              r.inputHash == r.provenance.inputSHA256, r.provenance.model == "htdemucs",
              r.provenance.backend == "mlx-metal", r.provenance.settings == .standard,
              ["drums", "bass", "other", "vocals"].contains(r.provenance.stem) else { throw AudioError.invalid("素材の位置情報が無効です。") }
        func object(_ hash: String) throws -> URL {
            guard MaterialHash.valid(hash), let row = try db.rows("SELECT path FROM blobs WHERE hash=?", [hash]).first else { throw AudioError.invalid("素材の音声情報がありません。") }
            let url = root.appendingPathComponent(row[0])
            guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().appendingPathComponent("objects").path + "/"),
                  try MaterialHash.file(url) == hash else { throw AudioError.invalid("保存音声が見つからないか、破損しています。") }
            return url
        }
        let input = try object(r.inputHash), original = try object(r.originalHash), stem = try object(r.stemHash), clip = try object(r.clipHash)
        try Self.validateAudio(original, frames: r.provenance.frames)
        try Self.validateAudio(stem, frames: r.provenance.frames)
        try Self.validateAudio(clip, frames: r.endFrame - r.startFrame)
        return MaterialRestoration(record: r, origin: MaterialOrigin(provenance: r.provenance,
            input: input, original: original, stem: stem, lease: nil, record: r, audioLease: acquireLease(r)), clip: clip)
    }
    /// A missing library never prevents a self-contained instrument from playing.
    func resolve(_ provenance: InstrumentProvenance) throws -> MaterialOrigin? {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.sqlite").path) else { return nil }
        let restored = try restore(provenance.material.id, includeDeleted: true)
        guard restored.record == provenance.material else { throw AudioError.invalid("楽器と素材ライブラリの来歴が一致しません。") }
        var origin = restored.origin
        origin.frameOffset = provenance.startFrame
        return origin
    }
    private static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    private static func validateAudio(_ url: URL, frames: Int64) throws {
        let asset = try AudioAsset.load(url), reader = try AVAudioFile(forReading: url)
        guard asset.sampleRate == 44100, asset.channels == 2, asset.bitDepth == 32, reader.length == frames else { throw AudioError.invalid("素材音声の形式・長さが一致しません。") }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 16384) else {
            throw AudioError.invalid("素材の検証メモリを確保できませんでした。")
        }
        while reader.framePosition < reader.length {
            try Task.checkCancellation()
            try reader.read(into: buffer, frameCount: 16384)
            guard buffer.frameLength > 0, let pcm = buffer.floatChannelData else { throw AudioError.invalid("素材音声を読み取れません。") }
            for c in 0..<2 { for f in 0..<Int(buffer.frameLength) where !pcm[c][f].isFinite { throw AudioError.invalid("素材音声に無効な値があります。") } }
        }
    }
}

final class MaterialDatabase {
    private var db: OpaquePointer?
    init(_ url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; db = nil
            throw AudioError.invalid("素材DBを開けませんでした。保存済みデータは保持しています。")
        }
        sqlite3_busy_timeout(db, 3000)
        do { try execute("PRAGMA foreign_keys=ON") } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    func backup(to destination: URL) throws {
        let partial = destination.appendingPathExtension("partial")
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: partial) } }
        do {
            let copy = try MaterialDatabase(partial)
            guard let backup = sqlite3_backup_init(copy.db, "main", db, "main") else { throw failure() }
            let status = sqlite3_backup_step(backup, -1)
            let finished = sqlite3_backup_finish(backup)
            guard status == SQLITE_DONE, finished == SQLITE_OK else { throw failure() }
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        complete = true
    }
    func execute(_ sql: String, _ args: [String] = []) throws { _ = try rows(sql, args) }
    func rows(_ sql: String, _ args: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in args.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { throw failure() }
        }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw failure() }
            result.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
            })
        }
    }
    private func failure() -> Error { AudioError.invalid("素材DBの読み書きに失敗しました。既存データを保持しています。バックアップを含む管理フォルダを確認してください。") }
}
