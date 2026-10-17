import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let sonicForgeEnsemble = UTType(exportedAs: "local.sonicforge.ensemble", conformingTo: .json)
}

struct EnsemblePartSnapshot {
    let name: String
    let instrument: EnsembleInstrument
    let performance: PerformanceDocument
    let gainDB: Double
    let muted: Bool
    var startBeat: Double = 0
    var repeatCount: Int = 1
}
struct EnsembleSnapshot {
    let tempo: Double
    let masterDB: Double
    let parts: [EnsemblePartSnapshot]
}
private struct EnsemblePartArchive: Codable {
    let name: String
    let instrumentName: String
    let instrument: InstrumentArchive
    let performance: PerformanceDocument
    let gainDB: Double
    let muted: Bool
    let startBeat: Double?
    let repeatCount: Int?
}
private struct EnsembleArchive: Codable {
    let version: Int
    let tempo: Double
    let masterDB: Double
    let parts: [EnsemblePartArchive]
}

/// Self-contained: embedded WAV and settings, never external instrument/performance paths.
enum EnsembleDocument {
    static let maximumBytes = 384 * 1024 * 1024
    static func validate(_ snapshot: EnsembleSnapshot) throws {
        guard snapshot.tempo.isFinite, (40...240).contains(snapshot.tempo),
              snapshot.masterDB.isFinite, (-60...0).contains(snapshot.masterDB), (1...4).contains(snapshot.parts.count) else {
            throw AudioError.invalid("構成のテンポ・Master音量・パート数が無効です。")
        }
        for part in snapshot.parts {
            guard (1...16).contains(part.repeatCount), part.startBeat.isFinite, (0...256).contains(part.startBeat), !part.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, part.name.count <= 80,
                  part.instrument.name.count <= 255, part.gainDB.isFinite, (-36...0).contains(part.gainDB),
                  (48...72).contains(part.instrument.root), part.instrument.envelope.isValid,
                  part.instrument.loop.isValid(frameCount: Int64(part.instrument.sample.buffer.frameLength), sampleRate: part.instrument.sample.buffer.format.sampleRate) else {
                throw AudioError.invalid("パート名・音量・楽器設定が無効です。パート名は1〜80文字にしてください。")
            }
            _ = try part.performance.events(root: part.instrument.root)
        }
    }
    static func save(_ snapshot: EnsembleSnapshot, to url: URL) throws {
        guard url.pathExtension.lowercased() == "sfensemble" else { throw AudioError.invalid("構成は.sfensemble形式で保存してください。") }
        try validate(snapshot)
        let parts = try snapshot.parts.map { part in
            EnsemblePartArchive(name: part.name, instrumentName: part.instrument.name,
                instrument: try InstrumentDocument.makeArchive(sample: part.instrument.sample, rootNote: part.instrument.root,
                    envelope: part.instrument.envelope, loop: part.instrument.loop),
                performance: part.performance, gainDB: part.gainDB, muted: part.muted, startBeat: part.startBeat, repeatCount: part.repeatCount)
        }
        let archive = EnsembleArchive(version: 3, tempo: snapshot.tempo, masterDB: snapshot.masterDB, parts: parts)
        let data = try JSONEncoder().encode(archive)
        guard data.count <= maximumBytes else { throw AudioError.invalid("構成ファイルは384 MB以下にしてください。") }
        try data.write(to: url, options: .atomic)
    }
    static func load(_ url: URL) throws -> EnsembleSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw AudioError.invalid("構成ファイルは384 MB以下にしてください。") }
        let archive = try JSONDecoder().decode(EnsembleArchive.self, from: Data(contentsOf: url))
        guard (1...3).contains(archive.version) else { throw AudioError.invalid("このバージョンの構成ファイルには対応していません。") }
        guard (1...4).contains(archive.parts.count), archive.tempo.isFinite, (40...240).contains(archive.tempo),
              archive.masterDB.isFinite, (-60...0).contains(archive.masterDB) else { throw AudioError.invalid("構成の設定が無効です。") }
        // Validate cheap metadata and performance before decoding any embedded audio.
        for part in archive.parts {
            guard (archive.version < 3 || part.repeatCount != nil), (1...16).contains(part.repeatCount ?? 1), (archive.version == 1 || part.startBeat != nil), (part.startBeat ?? 0).isFinite, (0...256).contains(part.startBeat ?? 0), !part.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, part.name.count <= 80,
                  part.instrumentName.count <= 255, part.gainDB.isFinite, (-36...0).contains(part.gainDB) else {
                throw AudioError.invalid("構成のパート名・楽器名・音量が無効です。")
            }
            _ = try part.performance.events(root: part.instrument.rootNote)
        }
        let parts = try archive.parts.map { part -> EnsemblePartSnapshot in
            let restored = try InstrumentDocument.restore(part.instrument)
            defer { try? FileManager.default.removeItem(at: restored.directory) }
            return EnsemblePartSnapshot(name: part.name,
                instrument: EnsembleInstrument(sample: restored.sample, root: restored.rootNote,
                    envelope: restored.envelope, loop: restored.loop, name: part.instrumentName),
                performance: part.performance, gainDB: part.gainDB, muted: part.muted, startBeat: archive.version == 1 ? 0 : part.startBeat!, repeatCount: archive.version < 3 ? 1 : part.repeatCount!)
        }
        let snapshot = EnsembleSnapshot(tempo: archive.tempo, masterDB: archive.masterDB, parts: parts)
        try validate(snapshot)
        return snapshot
    }
}
