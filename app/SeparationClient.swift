import Foundation
import AVFoundation
import Darwin

struct SeparationAudio: Decodable, Identifiable {
    let id: String
    let file: String
    let frames: Int64
    let sampleRate: Double
    let channels: Int
    var name: String { ["original": "元の曲", "drums": "ドラム", "bass": "ベース", "other": "その他の楽器", "vocals": "ボーカル"][id] ?? id }
}
struct SeparationManifest: Decodable {
    let version: Int
    let jobID: String
    let prepared: Bool
    let model: String
    let weightSHA256: String
    let audio: [SeparationAudio]?
    let inputSHA256: String?
    let versions: [String: String]?
    let gain: Double?
    let preprocessing: String?
    let backend: String?
    let settings: SeparationSettings?
}
struct SeparationProgress: Decodable {
    let version: Int
    let jobID: String
    let stage: String
    let message: String
}

final class SeparationProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    func launch(_ value: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        try value.run()
        process = value
    }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if let process, process.isRunning { process.terminate() }
    }
    func killAndWait() {
        lock.lock(); let value = process; stopped = true; lock.unlock()
        if let value, value.isRunning { kill(value.processIdentifier, SIGKILL); value.waitUntilExit() }
    }
}

struct SeparationClient {
    static let weightHash = "339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297"
    static func validate(_ directory: URL, jobID: String, prepare: Bool) throws -> SeparationManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 32768 else { throw AudioError.invalid("分離結果が大きすぎます。") }
        let manifest = try JSONDecoder().decode(SeparationManifest.self, from: Data(contentsOf: url))
        guard manifest.version == 1, manifest.jobID == jobID, manifest.prepared == prepare,
              manifest.model == "htdemucs", manifest.weightSHA256 == weightHash else { throw AudioError.invalid("分離結果の識別情報が一致しません。") }
        if prepare { return manifest }
        guard let hash = manifest.inputSHA256, MaterialHash.valid(hash),
              let gain = manifest.gain, gain.isFinite, gain > 0, gain <= 1,
              let versions = manifest.versions, !versions.isEmpty,
              versions.count <= 20, versions.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 80 && !$0.value.isEmpty && $0.value.count <= 100 }),
              manifest.backend == "mlx-metal", manifest.settings == SeparationSettings.standard,
              manifest.preprocessing == "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1" else {
            throw AudioError.invalid("分離結果の来歴が無効です。")
        }
        let expected: Set<String> = ["original", "drums", "bass", "other", "vocals"]
        guard let audio = manifest.audio, audio.count == 5, Set(audio.map(\.id)) == expected,
              Set(audio.map(\.frames)).count == 1 else { throw AudioError.invalid("分離した音源が揃っていません。") }
        for entry in audio {
            guard entry.file == entry.id + ".wav", entry.frames > 1, entry.frames <= 600 * 44100,
                  entry.sampleRate == 44100, entry.channels == 2 else { throw AudioError.invalid("分離音源の形式が無効です。") }
            let file = directory.appendingPathComponent(entry.file)
            guard file.resolvingSymlinksInPath().deletingLastPathComponent() == directory.resolvingSymlinksInPath() else { throw AudioError.invalid("分離音源の保存先が無効です。") }
            let asset = try AudioAsset.load(file)
            let reader = try AVAudioFile(forReading: file)
            guard asset.bitDepth == 32, asset.sampleRate == entry.sampleRate, asset.channels == entry.channels,
                  reader.length == entry.frames else { throw AudioError.invalid("分離音源の長さが一致しません。") }
            let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 16384)!
            while reader.framePosition < reader.length {
                try reader.read(into: buffer, frameCount: 16384)
                guard buffer.frameLength > 0, let values = buffer.floatChannelData else { throw AudioError.invalid("分離音源を読み取れません。") }
                for channel in 0..<2 {
                    for frame in 0..<Int(buffer.frameLength) where !values[channel][frame].isFinite { throw AudioError.invalid("分離音源に無効な値があります。") }
                }
            }
        }
        return manifest
    }

    func run(python: URL, worker: URL, cache: URL, source: URL?, directory: URL, jobID: String,
             control: SeparationProcess, update: @escaping @Sendable (String) async -> Void) async throws -> SeparationManifest {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard manager.isExecutableFile(atPath: python.path), manager.fileExists(atPath: worker.path) else { throw AudioError.invalid("分離用Pythonが見つかりません。実行環境の設定を確認してください。") }
        var request: [String: Any] = ["version": 1, "jobID": jobID, "cache": cache.path]
        if let source {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let file = try AVAudioFile(forReading: source)
            guard size <= 256 * 1024 * 1024, file.length > 1,
                  (1...2).contains(file.processingFormat.channelCount),
                  Double(file.length) / file.processingFormat.sampleRate <= 600 else { throw AudioError.invalid("10分以内・256 MB以下のモノラル／ステレオを選んでください。") }
            let free = try manager.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber
            guard (free?.int64Value ?? 0) >= 2 * 1024 * 1024 * 1024 else { throw AudioError.invalid("分離には2 GB以上の空き容量が必要です。") }
            let copied = directory.appendingPathComponent("input." + source.pathExtension.lowercased())
            try manager.copyItem(at: source.resolvingSymlinksInPath(), to: copied)
            request["input"] = copied.path
        }
        let requestURL = directory.appendingPathComponent("request.json")
        try JSONSerialization.data(withJSONObject: request).write(to: requestURL, options: .atomic)
        let process = Process()
        process.executableURL = python
        process.arguments = [worker.path, "--request", requestURL.path, "--mode", source == nil ? "prepare" : "separate"]
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"; env["PYTHONNOUSERSITE"] = "1"
        process.environment = env
        try Task.checkCancellation()
        try control.launch(process)
        let deadline = Date().addingTimeInterval(1800)
        var lastMessage = ""
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw AudioError.invalid("分離処理が30分以内に完了しませんでした。") }
                let progressURL = directory.appendingPathComponent("progress.json")
                if let size = try? progressURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                   let data = try? Data(contentsOf: progressURL),
                   let progress = try? JSONDecoder().decode(SeparationProgress.self, from: data),
                   progress.version == 1, progress.jobID == jobID, progress.message != lastMessage {
                    lastMessage = progress.message
                    await update(progress.message)
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else { throw AudioError.invalid("分離を完了できませんでした。固定版の実行環境・モデルの準備・入力音源を確認してください。") }
            return try await Task.detached(priority: .userInitiated) {
                let result = try Self.validate(directory, jobID: jobID, prepare: source == nil)
                if let source {
                    let input = directory.appendingPathComponent("input." + source.pathExtension.lowercased())
                    guard try MaterialHash.file(input) == result.inputSHA256 else { throw AudioError.invalid("元曲の内容が分離時と一致しません。") }
                }
                return result
            }.value
        } catch {
            control.terminate()
            for _ in 0..<20 where process.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            control.killAndWait()
            throw error
        }
    }
}
