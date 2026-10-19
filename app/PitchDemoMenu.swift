import SwiftUI

struct PitchDemoMenu: View {
    @ObservedObject var model: PlayerModel
    @State private var entries: [PitchCorpus.Entry] = []
    @State private var failure: String?
    @State private var pending: PitchCorpus.Entry?
    var body: some View {
        Menu("デモ") {
            Button("金属音デモを開く") { Task { await model.loadDemo() } }
            Menu("音程評価デモ") {
            Text("実録音・正解ラベル付き / 和音・打楽器")
            ForEach(["bass", "piano", "guitar", "chord", "percussion"], id: \.self) { group in
                Menu(["bass":"ベース", "piano":"ピアノ", "guitar":"ギター", "chord":"和音", "percussion":"打楽器"][group]!) {
                    ForEach(entries.filter { $0.group == group }) { entry in
                        Button(entry.label) {
                            if model.instrumentDirty { pending = entry } else { open(entry) }
                        }.accessibilityIdentifier("pitch.demo.\(entry.id)")
                    }
                }
            }
            if let failure { Text(failure) }
            }
        }
        .accessibilityIdentifier("pitch.demo")
        .help("公開録音を使った評価デモ。音名は配布元のラベルです。取り込み後に「音程を推定…」で比較できます。")
        .disabled(model.busy)
        .task {
            do {
                guard let directory = PitchCorpus.bundledDirectory else { throw AudioError.invalid("評価音源がありません。") }
                entries = try PitchCorpus.load(at: directory).entries
            } catch { failure = error.localizedDescription }
        }
        .confirmationDialog("編集中の楽器を評価音源に置き換えますか？", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("保存して開く") {
                let entry = pending; pending = nil
                Task { if await model.saveBeforeSeparationUse(), let entry { await model.loadPitchDemo(entry) } }
            }
            Button("保存せずに開く", role: .destructive) { if let entry = pending { pending = nil; open(entry) } }
            Button("キャンセル", role: .cancel) { pending = nil }
        }
    }
    private func open(_ entry: PitchCorpus.Entry) { Task { await model.loadPitchDemo(entry) } }
}
