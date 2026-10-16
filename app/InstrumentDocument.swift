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
    let envelope: ADSRParameters?
    let loop: SampleLoop?
}

struct RestoredInstrument {
    let loop: SampleLoop
    let envelope: ADSRParameters
    let rootNote: Int
    let sample: InstrumentSample
    let asset: AudioAsset
    let directory: URL
}

enum InstrumentDocument {
    static func save(sample: InstrumentSample, rootNote: Int, envelope: ADSRParameters = .standard, loop: SampleLoop? = nil, to url: URL) throws {
        guard url.pathExtension.lowercased() == "sfinstrument", (48...72).contains(rootNote), envelope.isValid else {
            throw AudioError.invalid("楽器の保存形式または基準音が無効です。")
        }
        let loop = loop ?? SampleLoop(endFrame: Int64(sample.buffer.frameLength))
        guard loop.isValid(frameCount: Int64(sample.buffer.frameLength), sampleRate: sample.buffer.format.sampleRate) else { throw AudioError.invalid("ループ範囲が無効です。") }
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
        let archive = InstrumentArchive(version: 4, rootNote: rootNote, sampleName: sample.name,
                                        sampleWAV: try Data(contentsOf: audioURL), envelope: envelope, loop: loop)
        let data = try JSONEncoder().encode(archive)
        try data.write(to: url, options: .atomic)
    }

    static func load(_ url: URL) throws -> RestoredInstrument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && size <= 96 * 1024 * 1024 else { throw AudioError.invalid("楽器ファイルのサイズが無効です（最大96 MB）。") }
        let archive = try JSONDecoder().decode(InstrumentArchive.self, from: Data(contentsOf: url))
        guard (1...4).contains(archive.version) else { throw AudioError.invalid("このバージョンの楽器ファイルには対応していません。") }
        let envelope = archive.version == 1 ? ADSRParameters.legacy : archive.envelope
        guard let envelope, envelope.isValid else { throw AudioError.invalid("ADSRの設定が無効です。") }
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
            let loop = archive.version < 3 ? SampleLoop(endFrame: Int64(sample.buffer.frameLength)) : archive.loop
            guard let loop, loop.isValid(frameCount: Int64(sample.buffer.frameLength), sampleRate: sample.buffer.format.sampleRate) else { throw AudioError.invalid("ループ範囲が無効です。") }
            return RestoredInstrument(loop: loop, envelope: envelope, rootNote: archive.rootNote, sample: sample, asset: asset, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
