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
    var frameOffset: Int64 = 0
    var record: MaterialRecord? = nil
    var audioLease: MaterialAudioLease? = nil
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

/// Portable metadata only. Audio remains embedded in the instrument document.
struct InstrumentProvenance: Codable, Equatable {
    let material: MaterialRecord
    let startFrame: Int64
    let endFrame: Int64
    var location: String {
        String(format: "%.3f–%.3f 秒 · %@", Double(startFrame) / material.provenance.sampleRate,
               Double(endFrame) / material.provenance.sampleRate, material.provenance.stem)
    }
    func validate(frames: Int64, sampleRate: Double) throws {
        let p = material.provenance
        guard UUID(uuidString: material.id) != nil, material.parentMaterialID.map({ UUID(uuidString: $0) != nil && $0 != material.id }) ?? true,
              !material.name.isEmpty, material.name.count <= 160, !p.sourceName.isEmpty, p.sourceName.count <= 255,
              UUID(uuidString: p.runID) != nil, p.model == "htdemucs", p.backend == "mlx-metal", p.settings == .standard,
              p.preprocessing == "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1",
              p.versions.count <= 20, !p.versions.isEmpty, p.versions.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 80 && !$0.value.isEmpty && $0.value.count <= 100 }),
              p.gain.isFinite, p.gain > 0, p.gain <= 1,
              ["drums", "bass", "other", "vocals"].contains(p.stem), p.frames > 1, p.frames <= 600 * 44100,
              p.sampleRate == 44100, sampleRate == p.sampleRate, material.inputHash == p.inputSHA256,
              [p.inputSHA256, p.weightSHA256, material.originalHash, material.stemHash, material.clipHash].allSatisfy(MaterialHash.valid),
              ["wav", "mp3"].contains(material.inputFormat),
              material.startFrame >= 0, material.endFrame > material.startFrame, material.endFrame <= p.frames,
              material.endFrame - material.startFrame <= 30 * 44100,
              startFrame >= 0, endFrame > startFrame, endFrame <= p.frames,
              endFrame - startFrame == frames, frames <= 30 * 44100 else {
            throw AudioError.invalid("楽器の来歴・元曲上の範囲が無効です。")
        }
    }
}

extension MaterialOrigin {
    func absolute(_ selection: AudioSelection) throws -> AudioSelection {
        guard frameOffset >= 0, frameOffset <= provenance.frames, selection.startFrame >= 0,
              selection.endFrame > selection.startFrame, selection.endFrame <= provenance.frames - frameOffset else {
            throw AudioError.invalid("素材の元曲位置を復元できません。")
        }
        return AudioSelection(startFrame: frameOffset + selection.startFrame, endFrame: frameOffset + selection.endFrame)
    }
}
