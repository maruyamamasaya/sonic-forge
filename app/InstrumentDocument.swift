import Foundation
import AVFoundation
import UniformTypeIdentifiers

extension UTType {
    static let sonicForgeInstrument = UTType(exportedAs: "local.sonicforge.instrument", conformingTo: .json)
}

private struct InstrumentArchive: Codable {
    let version: Int
    let rootNote: Int
    let sampleName: String
    let sampleWAV: Data
}

struct RestoredInstrument {
    let rootNote: Int
    let sample: InstrumentSample
    let asset: AudioAsset
    let directory: URL
}

enum InstrumentDocument {
    static func save(sample: InstrumentSample, rootNote: Int, to url: URL) throws {
        guard url.pathExtension.lowercased() == "sfinstrument", (48...72).contains(rootNote) else {
            throw AudioError.invalid("楽器の保存形式または基準音が無効です。")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Save-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("sample.wav")
        // Persist the installed PCM, not a reference to the original source file.
        do {
            var settings = sample.buffer.format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: audioURL, settings: settings)
            try file.write(from: sample.buffer)
        }
        let archive = InstrumentArchive(version: 1, rootNote: rootNote, sampleName: sample.name,
                                        sampleWAV: try Data(contentsOf: audioURL))
        let data = try JSONEncoder().encode(archive)
        try data.write(to: url, options: .atomic)
    }

    static func load(_ url: URL) throws -> RestoredInstrument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && size <= 96 * 1024 * 1024 else { throw AudioError.invalid("楽器ファイルのサイズが無効です（最大96 MB）。") }
        let archive = try JSONDecoder().decode(InstrumentArchive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw AudioError.invalid("このバージョンの楽器ファイルには対応していません。") }
        guard (48...72).contains(archive.rootNote), archive.sampleName.count <= 255,
              archive.sampleWAV.count <= 64 * 1024 * 1024 + 8192 else {
            throw AudioError.invalid("楽器の設定または同梱音源が無効です。")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Open-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let audioURL = directory.appendingPathComponent("sample.wav")
            try archive.sampleWAV.write(to: audioURL, options: .atomic)
            let asset = try AudioAsset.load(audioURL)
            let decoded = try InstrumentSample.load(url: audioURL)
            let sample = InstrumentSample(buffer: decoded.buffer, name: archive.sampleName, selection: decoded.selection)
            return RestoredInstrument(rootNote: archive.rootNote, sample: sample, asset: asset, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
