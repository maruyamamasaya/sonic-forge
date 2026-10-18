import AppKit
import Combine

@MainActor
final class PerformanceComposer: ObservableObject {
    enum Provider: String, CaseIterable, Identifiable {
        case codex = "Codex CLI", openai = "OpenAI API", external = "Other AI", demo = "Demo"
        var id: String { rawValue }
    }
    @Published var provider = Provider.codex { didSet { invalidate() } }
    @Published var prompt = "落ち着いた和音" { didSet { invalidate() } }
    @Published var apiKey = ""
    @Published var model = "gpt-4.1-mini"
    @Published var executable = CodexPerformanceClient.discover()
    @Published var externalJSON = "" { didSet { invalidate() } }
    @Published private(set) var generating = false
    @Published private(set) var candidate: PerformanceDocument?
    @Published private(set) var candidateRoot: Int?
    @Published private(set) var source: String?
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    typealias Generator = (PerformanceBrief) async throws -> PerformanceDocument

    func browseCodex() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.title = "Codexの実行ファイルを選択"
        if panel.runModal() == .OK, let url = panel.url { executable = CodexPerformanceClient.nativeExecutable(url)?.path ?? url.path }
    }
    func copyBrief(root: Int) {
        let brief = PerformanceBrief(prompt: prompt, root: root)
        guard (try? brief.validate()) != nil else { error = "指示を入力してください。"; return }
        let schema = (try? JSONSerialization.data(withJSONObject: PerformanceGeneration.schema, options: .prettyPrinted)) ?? Data()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(brief.instructions + "\nJSON Schema:\n" + (String(data: schema, encoding: .utf8) ?? ""), forType: .string)
    }
    func generate(root: Int, override: Generator? = nil) {
        guard !generating else { return }
        let brief = PerformanceBrief(prompt: prompt, root: root)
        do { try brief.validate() } catch { self.error = error.localizedDescription; return }
        invalidate()
        let token = generation, provider = self.provider, key = apiKey, model = self.model, executable = self.executable, json = externalJSON
        generating = true
        task = Task { [weak self] in
            do {
                let document: PerformanceDocument
                if let override { document = try await override(brief) }
                else {
                    switch provider {
                    case .codex: document = try await CodexPerformanceClient().generate(brief: brief, executable: executable)
                    case .openai: document = try await OpenAIPerformanceClient().generate(brief: brief, key: key, model: model)
                    case .external: document = try PerformanceGeneration.decode(Data(json.utf8), root: root)
                    case .demo: document = try PerformanceGeneration.demo(brief)
                    }
                }
                try Task.checkCancellation()
                let validated = try PerformanceGeneration.validate(document, root: root)
                guard let self, self.generation == token else { return }
                self.candidate = validated; self.candidateRoot = root; self.source = provider.rawValue
                self.generating = false; self.task = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.generating = false; self.task = nil
                self.error = error is CancellationError ? nil : error.localizedDescription
            }
        }
    }
    func cancel() { invalidate() }
    private func invalidate() {
        generation = UUID(); task?.cancel(); task = nil
        generating = false; candidate = nil; candidateRoot = nil; source = nil; error = nil
    }
}
