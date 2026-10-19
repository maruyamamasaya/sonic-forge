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
    var pan: Double = 0
    var eq: PartEQ = .flat
    var reverb: Double = 0
    var startBeat: Double = 0
    var repeatCount: Int = 1
    var sectionID: UUID? = nil
    var additionalClips: [EnsembleClip] = []
    var allClips: [EnsembleClip] {
        [EnsembleClip(performance: performance, startBeat: startBeat, repeatCount: repeatCount, sectionID: sectionID)] + additionalClips
    }
}
struct EnsembleSnapshot {
    let tempo: Double
    let masterDB: Double
    let parts: [EnsemblePartSnapshot]
    var sections: [EnsembleSection] = []
}
private struct EnsemblePartArchive: Codable {
    let name: String
    let instrumentName: String
    let instrument: InstrumentArchive
    let performance: PerformanceDocument
    let gainDB: Double
    let muted: Bool
    let reverb: Double?
    let eq: PartEQ?
    let pan: Double?
    let startBeat: Double?
    let repeatCount: Int?
    let sectionID: UUID?
    let additionalClips: [EnsembleClip]?
}
private struct EnsembleArchive: Codable {
    let version: Int
    let tempo: Double
    let masterDB: Double
    let parts: [EnsemblePartArchive]
    let sections: [EnsembleSection]?
}

/// Self-contained: embedded WAV and settings, never external instrument/performance paths.
enum EnsembleDocument {
    static let maximumBytes = 384 * 1024 * 1024
    static func validate(_ snapshot: EnsembleSnapshot) throws {
        guard snapshot.tempo.isFinite, (40...240).contains(snapshot.tempo),
              snapshot.masterDB.isFinite, (-60...0).contains(snapshot.masterDB), (1...4).contains(snapshot.parts.count) else {
            throw AudioError.invalid("構成のテンポ・Master音量・パート数が無効です。")
        }
        try EnsembleSections.validate(snapshot.sections)
        for part in snapshot.parts {
            guard (1...16).contains(part.repeatCount), part.startBeat.isFinite, (0...256).contains(part.startBeat), !part.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, part.name.count <= 80,
                  part.instrument.name.count <= 255, part.gainDB.isFinite, (-36...0).contains(part.gainDB), part.pan.isFinite, (-1...1).contains(part.pan), part.eq.isValid, PartReverb.isValid(part.reverb),
                  (48...72).contains(part.instrument.root), part.instrument.envelope.isValid,
                  part.instrument.loop.isValid(frameCount: Int64(part.instrument.sample.buffer.frameLength), sampleRate: part.instrument.sample.buffer.format.sampleRate) else {
                throw AudioError.invalid("パート名・音量・楽器設定が無効です。パート名は1〜80文字にしてください。")
            }
            _ = try part.performance.events(root: part.instrument.root)
            try EnsembleClips.validate(part.allClips, root: part.instrument.root, sections: snapshot.sections)
        }
    }
    static func save(_ snapshot: EnsembleSnapshot, to url: URL) throws {
        guard url.pathExtension.lowercased() == "sfensemble" else { throw AudioError.invalid("構成は.sfensemble形式で保存してください。") }
        try validate(snapshot)
        let parts = try snapshot.parts.map { part in
            EnsemblePartArchive(name: part.name, instrumentName: part.instrument.name,
                instrument: try InstrumentDocument.makeArchive(sample: part.instrument.sample, rootNote: part.instrument.root,
                    envelope: part.instrument.envelope, loop: part.instrument.loop),
                performance: part.performance, gainDB: part.gainDB, muted: part.muted, reverb: part.reverb, eq: part.eq, pan: part.pan, startBeat: part.startBeat, repeatCount: part.repeatCount, sectionID: part.sectionID, additionalClips: part.additionalClips)
        }
        let archive = EnsembleArchive(version: 8, tempo: snapshot.tempo, masterDB: snapshot.masterDB, parts: parts, sections: snapshot.sections)
        let data = try JSONEncoder().encode(archive)
        guard data.count <= maximumBytes else { throw AudioError.invalid("構成ファイルは384 MB以下にしてください。") }
        try data.write(to: url, options: .atomic)
    }
    static func load(_ url: URL) throws -> EnsembleSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw AudioError.invalid("構成ファイルは384 MB以下にしてください。") }
        let archive = try JSONDecoder().decode(EnsembleArchive.self, from: Data(contentsOf: url))
        guard (1...8).contains(archive.version) else { throw AudioError.invalid("このバージョンの構成ファイルには対応していません。") }
        guard (1...4).contains(archive.parts.count), archive.tempo.isFinite, (40...240).contains(archive.tempo),
              archive.masterDB.isFinite, (-60...0).contains(archive.masterDB) else { throw AudioError.invalid("構成の設定が無効です。") }
        guard archive.version < 4 || archive.sections != nil else { throw AudioError.invalid("セクション情報がありません。") }
        let sections = archive.version < 4 ? [] : archive.sections!
        try EnsembleSections.validate(sections)
        // Validate cheap metadata and performance before decoding any embedded audio.
        for part in archive.parts {
            guard (archive.version < 3 || part.repeatCount != nil), (1...16).contains(part.repeatCount ?? 1), (archive.version == 1 || part.startBeat != nil), (part.startBeat ?? 0).isFinite, (0...256).contains(part.startBeat ?? 0), !part.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, part.name.count <= 80,
                  part.instrumentName.count <= 255, part.gainDB.isFinite, (-36...0).contains(part.gainDB),
                  (archive.version < 6 || part.pan != nil), (part.pan ?? 0).isFinite, (-1...1).contains(part.pan ?? 0),
                  (archive.version < 7 || part.eq != nil), (part.eq ?? .flat).isValid, (archive.version < 8 || part.reverb != nil), PartReverb.isValid(part.reverb ?? 0) else {
                throw AudioError.invalid("構成のパート名・楽器名・音量が無効です。")
            }
            _ = try part.performance.events(root: part.instrument.rootNote)
            guard archive.version < 5 || part.additionalClips != nil else { throw AudioError.invalid("演奏クリップ情報がありません。") }
            let primary = EnsembleClip(performance: part.performance, startBeat: archive.version == 1 ? 0 : part.startBeat ?? 0,
                repeatCount: archive.version < 3 ? 1 : part.repeatCount ?? 1, sectionID: archive.version < 4 ? nil : part.sectionID)
            try EnsembleClips.validate([primary] + (archive.version < 5 ? [] : part.additionalClips!), root: part.instrument.rootNote, sections: sections)
        }
        let parts = try archive.parts.map { part -> EnsemblePartSnapshot in
            let restored = try InstrumentDocument.restore(part.instrument)
            defer { try? FileManager.default.removeItem(at: restored.directory) }
            return EnsemblePartSnapshot(name: part.name,
                instrument: EnsembleInstrument(sample: restored.sample, root: restored.rootNote,
                    envelope: restored.envelope, loop: restored.loop, name: part.instrumentName),
                performance: part.performance, gainDB: part.gainDB, muted: part.muted, pan: archive.version < 6 ? 0 : part.pan!, eq: archive.version < 7 ? .flat : part.eq!, reverb: archive.version < 8 ? 0 : part.reverb!, startBeat: archive.version == 1 ? 0 : part.startBeat!, repeatCount: archive.version < 3 ? 1 : part.repeatCount!, sectionID: archive.version < 4 ? nil : part.sectionID, additionalClips: archive.version < 5 ? [] : part.additionalClips!)
        }
        let snapshot = EnsembleSnapshot(tempo: archive.tempo, masterDB: archive.masterDB, parts: parts, sections: sections)
        try validate(snapshot)
        return snapshot
    }
}
