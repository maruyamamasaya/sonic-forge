import Foundation
import CryptoKit

/// A job survives replacement while an adopted waveform still references it.
final class SeparationLease: @unchecked Sendable {
    let directory: URL
    init(_ directory: URL) { self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

struct SeparationSettings: Codable, Equatable {
    let shifts: Int
    let overlap: Double
    let segment: Double
    let batch_size: Int
    let attention_precision: String
    let compile: Bool
    static let standard = SeparationSettings(shifts: 0, overlap: 0.25, segment: 7.8,
        batch_size: 1, attention_precision: "fp32", compile: true)
}

struct MaterialProvenance: Codable, Equatable {
    let sourceName: String
    let inputSHA256: String
    let runID: String
    let model: String
    let backend: String
    let settings: SeparationSettings
    let weightSHA256: String
    let versions: [String: String]
    let gain: Double
    let preprocessing: String
    let stem: String
    let frames: Int64
    let sampleRate: Double
}

struct MaterialOrigin {
    let provenance: MaterialProvenance
    let input: URL
    let original: URL
    let stem: URL
    let lease: SeparationLease?
}

enum MaterialHash {
    static func file(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func valid(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
}
