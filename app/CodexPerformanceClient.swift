import Foundation
import Darwin

struct CodexPerformanceClient {
    static func nativeExecutable(_ url: URL) -> URL? {
        let resolved = url.resolvingSymlinksInPath()
        if resolved.pathExtension == "js" {
            let package = resolved.deletingLastPathComponent().deletingLastPathComponent()
            #if arch(arm64)
            let arch = "arm64", triple = "aarch64"
            #else
            let arch = "x64", triple = "x86_64"
            #endif
            let suffix = "vendor/\(triple)-apple-darwin/bin/codex"
            for candidate in [package.appendingPathComponent("node_modules/@openai/codex-darwin-\(arch)/" + suffix),
                              package.appendingPathComponent(suffix)] {
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
            return nil
        }
        return FileManager.default.isExecutableFile(atPath: resolved.path) ? resolved : nil
    }
    static func discover() -> String {
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].map { URL(fileURLWithPath: $0) }
        let nvm = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        for version in (try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? [] {
            candidates.append(version.appendingPathComponent("bin/codex"))
        }
        return candidates.compactMap { nativeExecutable($0) }.first?.path ?? ""
    }
    static func arguments(directory: URL, schema: URL, output: URL) -> [String] {
        ["exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
         "--disable", "shell_tool", "--disable", "unified_exec", "--disable", "apps", "--disable", "hooks",
         "-c", "web_search=\"disabled\"", "--cd", directory.path,
         "--output-schema", schema.path, "--output-last-message", output.path, "-"]
    }
    func generate(brief: PerformanceBrief, executable: String, timeout: Double = 120) async throws -> PerformanceDocument {
        try brief.validate()
        guard let binary = Self.nativeExecutable(URL(fileURLWithPath: executable)), !executable.isEmpty else {
            throw AudioError.invalid("Codex CLIが見つかりません。インストール済みのcodexを選択してください。")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Generate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = directory.appendingPathComponent("schema.json"), output = directory.appendingPathComponent("performance.json")
        let input = directory.appendingPathComponent("brief.txt")
        try JSONSerialization.data(withJSONObject: PerformanceGeneration.schema).write(to: schema)
        try Data(brief.instructions.utf8).write(to: input)
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = binary
        process.arguments = Self.arguments(directory: directory, schema: schema, output: output)
        process.currentDirectoryURL = directory
        process.standardInput = handle
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw AudioError.invalid("Codex CLIを起動できませんでした。実行ファイルを確認してください。") }
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw AudioError.invalid("Codex CLIが時間内に完了しませんでした。ログイン状態・接続を確認してください。") }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            // Stop the native process before removing its temporary workspace.
            for _ in 0..<20 where process.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw error
        }
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw AudioError.invalid("Codex CLIの生成が完了しませんでした。ターミナルでcodex loginを確認し、対応版CLIで再試行してください。")
        }
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= PerformanceGeneration.byteLimit else { throw AudioError.invalid("生成結果が1 MBを超えました。") }
        return try PerformanceGeneration.decode(Data(contentsOf: output), root: brief.root)
    }
}
