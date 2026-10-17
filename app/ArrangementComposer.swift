import AppKit
import Combine

@MainActor
final class ArrangementComposer: ObservableObject {
    @Published var prompt = "イントロは薄く、Aメロで動きを加えて、サビで厚く。" { didSet { cancel() } }
    @Published var externalJSON = "" { didSet { cancel() } }
    @Published private(set) var generating = false
    @Published private(set) var candidate: ArrangementProposal?
    @Published private(set) var brief: ArrangementBrief?
    @Published private(set) var preview: EnsembleSnapshot?
    @Published private(set) var source: String?
    @Published var error: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    typealias Generator = (ArrangementBrief) async throws -> ArrangementProposal

    func copyBrief(ensemble: EnsembleModel) {
        do {
            let brief = try ensemble.arrangementBrief(prompt: prompt)
            let schema = try JSONSerialization.data(withJSONObject: ArrangementGeneration.schema, options: [.prettyPrinted, .sortedKeys])
            let text = try brief.instructions + "\nJSON Schema:\n" + String(decoding: schema, as: UTF8.self)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func generate(ensemble: EnsembleModel, connection: PerformanceComposer, override: Generator? = nil) {
        guard !generating, ensemble.canEdit else { return }
        cancel()
        do {
            let brief = try ensemble.arrangementBrief(prompt: prompt)
            let instructions = try brief.instructions
            let token = generation, provider = connection.provider, key = connection.apiKey, model = connection.model
            let executable = connection.executable, json = externalJSON
            generating = true
            task = Task { [weak self, weak ensemble] in
                do {
                    let proposal: ArrangementProposal
                    if let override { proposal = try await override(brief) }
                    else {
                        switch provider {
                        case .demo: proposal = try ArrangementGeneration.demo(brief)
                        case .external: proposal = try ArrangementGeneration.decode(Data(json.utf8), brief: brief)
                        case .codex:
                            let data = try await CodexPerformanceClient().generateJSON(instructions: instructions,
                                schema: ArrangementGeneration.schema, executable: executable)
                            proposal = try ArrangementGeneration.decode(data, brief: brief)
                        case .openai:
                            let request = try OpenAIPerformanceClient.jsonRequest(instructions: instructions,
                                schema: ArrangementGeneration.schema, name: "sonicforge_arrangement", key: key, model: model, maxTokens: 16000)
                            let data = try await OpenAIPerformanceClient().generateJSON(request)
                            proposal = try ArrangementGeneration.decode(data, brief: brief)
                        }
                    }
                    try Task.checkCancellation()
                    let snapshot = try ArrangementGeneration.materialize(proposal, brief: brief)
                    guard let self, self.generation == token else { return }
                    guard let ensemble, ensemble.arrangementRevision == brief.revision else {
                        throw AudioError.invalid("生成中に構成が変更されました。現在の構成から再生成してください。")
                    }
                    self.candidate = proposal; self.preview = snapshot; self.brief = brief
                    self.source = provider == .openai ? "OpenAI API · \(model)" : provider.rawValue
                    self.generating = false; self.task = nil
                } catch {
                    guard let self, self.generation == token else { return }
                    self.generating = false; self.task = nil
                    self.error = error is CancellationError ? nil : error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func adopt(ensemble: EnsembleModel) -> Bool {
        guard !generating, let candidate, let brief else { return false }
        guard ensemble.applyArrangement(candidate, brief: brief) else { error = ensemble.error; return false }
        cancel(); return true
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; generating = false
        candidate = nil; brief = nil; preview = nil; source = nil; error = nil
    }
}
