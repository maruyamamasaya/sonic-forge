import Foundation
import CryptoKit

/// Small, licensed recordings shared by the offline demo and repeatable evaluation.
struct PitchCorpus: Decodable {
    struct Entry: Decodable, Identifiable {
        let id: String
        let group: String
        let label: String
        let file: String
        let notes: [Int]
        let kind: String // single / chord / percussion
        let sha256: String
    }
    let version: Int
    let entries: [Entry]
    static func load(at directory: URL) throws -> PitchCorpus {
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard value.version == 1, !value.entries.isEmpty, Set(value.entries.map(\.id)).count == value.entries.count,
              value.entries.allSatisfy({ !$0.id.isEmpty && !$0.label.isEmpty && $0.file == $0.id + ".wav" && !$0.file.contains("/") && !$0.file.contains("..") && ["single","chord","percussion"].contains($0.kind) && $0.notes.allSatisfy { (0...127).contains($0) } && ($0.kind != "single" || $0.notes.count == 1) }) else { throw AudioError.invalid("評価音源の一覧が無効です。") }
        return value
    }
    static var bundledDirectory: URL? { Bundle.main.resourceURL?.appendingPathComponent("PitchCorpus", isDirectory: true) }
    static func verifiedURL(_ entry: Entry, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(entry.file)
        let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        guard hash == entry.sha256 else { throw AudioError.invalid("評価音源のハッシュが一致しません。") }
        return url
    }
}
