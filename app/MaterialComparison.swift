import Foundation
import AVFoundation

enum MaterialPreviewKind: String, CaseIterable, Identifiable {
    case clip, original, stem
    var id: String { rawValue }
    var name: String {
        switch self { case .clip: return "素材"; case .original: return "元曲"; case .stem: return "分離パート" }
    }
}

/// All candidates start at local frame zero and end exactly at the saved boundary.
final class MaterialComparison: @unchecked Sendable {
    let directory: URL
    let record: MaterialRecord
    let audioLease: MaterialAudioLease?
    init(directory: URL, record: MaterialRecord, audioLease: MaterialAudioLease? = nil) { self.directory = directory; self.record = record; self.audioLease = audioLease }
    func url(_ kind: MaterialPreviewKind) -> URL { directory.appendingPathComponent(kind.rawValue + ".wav") }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

extension MaterialStore {
    func comparison(_ id: String) throws -> MaterialComparison {
        try Task.checkCancellation()
        let restored = try restore(id, includeDeleted: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-MaterialPreview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = MaterialComparison(directory: directory, record: restored.record, audioLease: restored.origin.audioLease)
        try FileManager.default.copyItem(at: restored.clip, to: result.url(.clip))
        for (kind, source) in [(MaterialPreviewKind.original, restored.origin.original), (.stem, restored.origin.stem)] {
            try Task.checkCancellation()
            try SelectionAudio.write(source: source, selection: restored.record.selection, to: result.url(kind))
        }
        try Task.checkCancellation()
        for kind in MaterialPreviewKind.allCases {
            let file = try AVAudioFile(forReading: result.url(kind))
            guard file.length == restored.record.selection.frameCount, file.processingFormat.sampleRate == 44100,
                  file.processingFormat.channelCount == 2 else { throw AudioError.invalid("比較用音声の位置・長さが一致しません。") }
        }
        return result
    }
}
