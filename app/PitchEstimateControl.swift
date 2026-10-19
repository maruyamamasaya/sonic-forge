import SwiftUI

struct PitchEstimateControl: View {
    let sample: InstrumentSample
    let root: Int
    let canApply: Bool
    var beforeAnalysis: () -> Void = {}
    let apply: (Int) -> Void
    @StateObject private var analysis = PitchAnalysis()
    @State private var presented = false
    var body: some View {
        Button("音程を推定…") { beforeAnalysis(); presented = true }
            .controlSize(.small).disabled(!canApply)
            .accessibilityIdentifier("pitch.estimate")
            .help("取り込み済みの楽器音源から基準音の候補を調べます。波形の選択を使う場合は先に楽器へ取り込んでください。採用するまで基準音は変えません。")
            .popover(isPresented: $presented) {
                PitchEstimatePanel(sample: sample, root: root, canApply: canApply, analysis: analysis) { note in
                    guard analysis.canApply(to: sample, note: note), canApply else { return }
                    apply(note); presented = false
                } close: { presented = false }
            }
            .onChange(of: ObjectIdentifier(sample.buffer)) { _, _ in presented = false; analysis.invalidate() }
            .onDisappear { analysis.cancel() }
    }
}

private struct PitchEstimatePanel: View {
    let sample: InstrumentSample
    let root: Int
    let canApply: Bool
    @ObservedObject var analysis: PitchAnalysis
    let apply: (Int) -> Void
    let close: () -> Void
    @State private var selectedRoot: Int
    init(sample: InstrumentSample, root: Int, canApply: Bool, analysis: PitchAnalysis, apply: @escaping (Int)->Void, close: @escaping ()->Void) {
        self.sample = sample; self.root = root; self.canApply = canApply; self.analysis = analysis
        self.apply = apply; self.close = close
        _selectedRoot = State(initialValue: root)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("基準音の候補").font(.headline); Spacer(); Button("閉じる", action: close).accessibilityIdentifier("pitch.close") }
            Text("取り込み済み: \(sample.name)").font(.caption).lineLimit(2)
            Text("現在の基準音: \(NotePitch.name(root)) · MIDI \(root)").font(.caption).foregroundStyle(.secondary)
            if analysis.running {
                HStack { ProgressView().controlSize(.small); Text("音程を解析中…"); Spacer(); Button("中止") { analysis.cancel() }.accessibilityIdentifier("pitch.cancel") }
            } else {
                if let result = analysis.result {
                    Text(result.reliability.rawValue).font(.subheadline.bold()).accessibilityIdentifier("pitch.status")
                    ForEach(result.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(NotePitch.name(candidate.note)) · MIDI \(candidate.note) · \(String(format: "%.2f", candidate.frequency)) Hz")
                                .font(.system(.body, design: .monospaced)).accessibilityIdentifier("pitch.candidate.\(candidate.note)")
                            Text(String(format: "基準周波数から %+.1f セント（100セント＝半音）", candidate.cents)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let note = result.primary?.note, !NotePitch.rootRange.contains(note) {
                        Text("候補は設定範囲C1〜C7の外です。別の区間か手動設定を確認してください。").font(.caption).foregroundStyle(.orange)
                    }
                    Text(result.warning).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if result.candidates.isEmpty { Text("候補はありません。下で手動指定することもできます。").font(.caption) }
                    HStack {
                        Picker("採用する基準音", selection: $selectedRoot) {
                            ForEach(NotePitch.rootRange, id: \.self) { Text("\(NotePitch.name($0)) · \($0)").tag($0) }
                        }.accessibilityIdentifier("pitch.root")
                        Button(result.primary.map { NotePitch.rootRange.contains($0.note) } == true ? "採用" : "手動設定を適用") { apply(selectedRoot) }
                            .disabled(!canApply || !analysis.canApply(to: sample, note: selectedRoot))
                            .accessibilityIdentifier("pitch.apply")
                    }
                    Text("候補は修正できます。採用は音名の対応付けで、音声の自動調律ではありません。").font(.caption).foregroundStyle(.secondary)
                }
                if let message = analysis.message { Text(message).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("pitch.error") }
                Button("もう一度推定") { Task { await analysis.analyze(sample) } }.accessibilityIdentifier("pitch.retry")
            }
        }
        .padding(18).frame(width: 390)
        .task {
            if analysis.source != ObjectIdentifier(sample.buffer) || analysis.result == nil { await analysis.analyze(sample) }
            chooseCandidate()
        }
        .onChange(of: analysis.result) { _, _ in chooseCandidate() }
        .onDisappear { analysis.cancel() }
    }
    private func chooseCandidate() {
        if let note = analysis.result?.primary?.note, NotePitch.rootRange.contains(note) { selectedRoot = note }
    }
}
