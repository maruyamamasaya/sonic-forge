import Foundation
import Darwin
import AVFoundation

/// Render beside the destination, then atomically publish the finished WAV.
enum WAVExport {
    static func write(source: URL, selection: AudioSelection, to destination: URL) throws {
        guard destination.pathExtension.lowercased() == "wav" else {
            throw AudioError.invalid("書き出し先には.wavファイルを指定してください。")
        }
        guard !sameFile(source, destination) else {
            throw AudioError.invalid("元の音源には上書きできません。別の名前で保存してください。")
        }
        // Float32 export must remain within the application's import limit.
        let sourceAsset = try AVAudioFile(forReading: source).processingFormat.channelCount
        guard selection.frameCount > 0,
              selection.frameCount <= (256 * 1024 * 1024 - 4096) / Int64(sourceAsset) / 4 else {
            throw AudioError.invalid("書き出すWAVが256 MBを超えます。選択範囲を短くしてください。")
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".sonicforge-export-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try SelectionAudio.write(source: source, selection: selection, to: temporary)
        // Recheck source identity immediately before replacement.
        guard !sameFile(source, destination) else {
            throw AudioError.invalid("元の音源には上書きできません。別の名前で保存してください。")
        }
        let status = temporary.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in Darwin.rename(from!, to!) }
        }
        if status != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    private static func sameFile(_ first: URL, _ second: URL) -> Bool {
        let a = first.resolvingSymlinksInPath().standardizedFileURL
        let b = second.resolvingSymlinksInPath().standardizedFileURL
        if a == b { return true }
        guard let aa = try? FileManager.default.attributesOfItem(atPath: a.path),
              let bb = try? FileManager.default.attributesOfItem(atPath: b.path) else { return false }
        return (aa[.systemNumber] as? NSNumber) == (bb[.systemNumber] as? NSNumber)
            && (aa[.systemFileNumber] as? NSNumber) == (bb[.systemFileNumber] as? NSNumber)
    }
}
