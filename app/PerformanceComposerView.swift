import SwiftUI

struct PerformanceComposerView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var midi: MIDIInput
    @ObservedObject var composer: PerformanceComposer
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReplace = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(accent)
                Text("AIで演奏案を作る").font(.system(size: 22, weight: .medium))
                Spacer()
                Button("閉じる") { composer.cancel(); dismiss() }.buttonStyle(StudioButton())
            }
            HStack {
                Picker("生成方式", selection: $composer.provider) {
                    ForEach(PerformanceComposer.Provider.allCases) { Text(JapaneseUI.provider($0.rawValue)).tag($0) }
                }.frame(width: 245).disabled(composer.generating)
                Spacer()
                Text("4小節・\(NotePitch.name(model.rootNote))・最大8音").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Group {
                switch composer.provider {
                case .codex:
                    HStack {
                        TextField("Codexの実行ファイル", text: $composer.executable).textFieldStyle(.roundedBorder)
                        Button("選択…") { composer.browseCodex() }
                    }
                    Text("ログイン済みCodexへ指示と基準音を送信します。音声は添付しません。")
                case .openai:
                    HStack {
                        SecureField("OpenAI APIキー・終了までメモリ内のみ", text: $composer.apiKey).textFieldStyle(.roundedBorder)
                        TextField("モデル", text: $composer.model).textFieldStyle(.roundedBorder).frame(width: 170)
                    }
                    Text("OpenAIへ指示と基準音を送信します。API利用料は別途発生し、キーは終了までメモリ内だけで保持します。")
                case .external:
                    HStack {
                        Text("他のAIへ指示を渡し、返ってきた演奏JSONを貼り付けてください。")
                        Spacer()
                        Button("指示をコピー") { composer.copyBrief(root: model.rootNote) }
                    }
                case .demo:
                    Text("接続不要の固定デモ2種類です。「落ち着いた和音」「跳ねたフレーズ」を試せます。AI生成ではありません。")
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary).disabled(composer.generating)
            Text("作りたい演奏を言葉で入力").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            TextEditor(text: $composer.prompt).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 75).background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityIdentifier("Performance instruction").accessibilityLabel("演奏の指示").disabled(composer.generating)
            HStack {
                Button("落ち着いた和音") { composer.prompt = "落ち着いた和音。ゆっくり、柔らかい強弱で。" }
                Button("少し跳ねたフレーズ") { composer.prompt = "少し跳ねたフレーズ。軽いスウィングと強弱をつけて。" }
                Spacer()
                if composer.generating {
                    ProgressView().controlSize(.small)
                    Button("生成を中止") { composer.cancel() }
                } else {
                    Button(composer.provider == .external ? "JSONを検証" : composer.provider == .demo ? "デモ案を作る" : "候補を生成") {
                        composer.generate(root: model.rootNote)
                    }.buttonStyle(StudioButton(primary: true)).disabled(model.instrumentSample == nil || model.busy)
                }
            }.controlSize(.small)
            if composer.provider == .external {
                TextEditor(text: $composer.externalJSON).font(.system(size: 10, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).frame(height: 110).background(.black.opacity(0.2)).accessibilityIdentifier("Generated performance JSON").accessibilityLabel("演奏案のJSON")
                    .disabled(composer.generating)
            } else if let candidate = composer.candidate {
                PerformanceRoll(document: candidate, accent: accent).frame(height: 130)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: composer.generating ? "waveform" : "pianokeys").font(.system(size: 24)).foregroundStyle(accent)
                    Text(composer.generating ? "演奏案を作成中…" : "雰囲気・リズム・フレーズを入力してください")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 130).background(.black.opacity(0.12))
            }
            if let candidate = composer.candidate {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        Text("\(JapaneseUI.provider(composer.source ?? "")) · \(candidate.notes.count) 音符・\(candidate.tempo.formatted()) BPM・検証済み")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("採用して再生") {
                        if midi.performanceDirty { confirmReplace = true } else { useCandidate() }
                    }.buttonStyle(StudioButton(primary: true)).disabled(model.busy || midi.performing)
                }
            }
            if let error = composer.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3).help(error) }
            Spacer(minLength: 0)
            Text("候補を確認して採用できます。採用後は「演奏編集…」で調整・保存できます。楽器は保ちます。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 780, height: 640)
            .background(Color(red: 0.075, green: 0.09, blue: 0.105)).preferredColorScheme(.dark)
            .onDisappear { composer.cancel() }
            .confirmationDialog("未保存の演奏を置き換えますか？", isPresented: $confirmReplace) {
                Button("置き換えて再生", role: .destructive) { useCandidate() }
                Button("キャンセル", role: .cancel) { }
            } message: { Text("元の演奏を残す場合はキャンセルし、「演奏編集…」→「保存…」で先に保存してください。") }
    }
    private func useCandidate() {
        guard let candidate = composer.candidate, composer.candidateRoot == model.rootNote else {
            composer.error = "楽器の基準音が変わりました。もう一度生成してください。"; return
        }
        guard midi.applyGeneratedPerformance(candidate, root: model.rootNote) else { composer.error = midi.error; return }
        onUse()
        dismiss()
    }
}

private struct PerformanceRoll: View {
    let document: PerformanceDocument
    let accent: Color
    var body: some View {
        Canvas { context, size in
            let low = (document.notes.map(\.pitch).min() ?? 48) - 2
            let high = (document.notes.map(\.pitch).max() ?? 72) + 2
            for beat in 0...16 {
                var path = Path(); let x = size.width * Double(beat) / 16
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(beat % 4 == 0 ? 0.15 : 0.05)), lineWidth: 1)
            }
            for note in document.notes {
                let row = size.height / Double(high - low + 1)
                let rect = CGRect(x: size.width * note.beat / 16, y: Double(high - note.pitch) * row,
                                  width: max(2, size.width * note.duration / 16 - 1), height: max(2, row - 1))
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent.opacity(0.3 + Double(note.velocity) / 180)))
            }
        }.background(.black.opacity(0.2)).accessibilityIdentifier("Generated performance piano roll, \(document.notes.count) notes across four bars").accessibilityLabel("生成した演奏の音符表示、\(document.notes.count)音符・4小節")
    }
}
