import SwiftUI

struct ArrangementComposerView: View {
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var connection: PerformanceComposer
    @ObservedObject var composer: ArrangementComposer
    let wood: WorkspaceWood
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReplace = false
    private let accent = Color(red: 0.94, green: 0.81, blue: 0.55)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AIで編曲案を作る").font(.custom("Georgia", size: 23))
                    Text("今ある楽器で曲の展開を考える").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { composer.cancel(); dismiss() }
            }.padding(18).foregroundStyle(wood.ink).environment(\.colorScheme, wood.scheme)
                .background(WoodSurface(wood: wood, horizontalGrain: true))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("生成方式", selection: $connection.provider) {
                            ForEach(PerformanceComposer.Provider.allCases) { Text(JapaneseUI.provider($0.rawValue)).tag($0) }
                        }.frame(width: 245).disabled(composer.generating)
                        Spacer()
                        Text("\(ensemble.parts.count) 楽器・最大8セクション").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    connectionSettings
                    TextEditor(text: $composer.prompt).font(.system(size: 14)).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 62).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("Arrangement instruction").accessibilityLabel("編曲の指示").disabled(composer.generating)
                    HStack {
                        Button("薄いイントロ → 厚いサビ") { composer.prompt = "イントロは薄く、Aメロで動きを加えて、サビで厚く。" }
                        Button("均一な構成") { composer.prompt = "全パートを各セクションで使う均一な構成。" }
                        Spacer()
                        if composer.generating {
                            ProgressView().controlSize(.small)
                            Button("生成を中止") { composer.cancel() }
                        } else {
                            Button(connection.provider == .external ? "JSONを検証" : connection.provider == .demo ? "デモ案を作る" : "候補を生成") {
                                composer.generate(ensemble: ensemble, connection: connection)
                            }.buttonStyle(CabinetButton(primary: true)).disabled(!ensemble.canEdit || ensemble.parts.isEmpty)
                        }
                    }
                    if connection.provider == .external {
                        TextEditor(text: $composer.externalJSON).font(.system(size: 10, design: .monospaced)).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 80).background(.black.opacity(0.2))
                            .accessibilityIdentifier("Generated arrangement JSON").accessibilityLabel("編曲案のJSON").disabled(composer.generating)
                    }
                    if let proposal = composer.candidate, let snapshot = composer.preview, let brief = composer.brief {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(proposal.name).font(.system(size: 17, weight: .medium))
                                Text("\(JapaneseUI.provider(composer.source ?? ""))・検証済み・\(proposal.tempo.formatted()) BPM · \(proposal.sections.reduce(0) { $0 + $1.beats }.formatted()) 拍")
                                    .font(.system(size: 11)).foregroundStyle(accent)
                            }
                            Spacer()
                            Text("\(brief.snapshot.sections.count) → \(proposal.sections.count) セクション\n\(brief.snapshot.parts.reduce(0) { $0 + $1.allClips.count }) → \(proposal.parts.reduce(0) { $0 + $1.clips.count }) クリップ")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(proposal.summary).font(.system(size: 12)).textSelection(.enabled)
                        ArrangementPreview(snapshot: snapshot).frame(height: 250)
                        Text("音符は押鍵の長さを表示します。ペダルと離鍵後の余韻は再生時に反映します。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(accent)
                            Text(composer.generating ? "編曲案を作成中…" : "どのように曲を展開するか入力してください")
                            Text("区切り・入り方・音符・音量を確認してから採用できます。").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 210).background(.black.opacity(0.14))
                    }
                    if let error = composer.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(18)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("採用するとセクション・全クリップ・テンポ・パート音量を置き換えます。")
                    Text("楽器と全体音量は保ちます。元を残す場合は先に構成を保存してください。").foregroundStyle(.secondary)
                }.font(.system(size: 10))
                Spacer()
                Button("現在の構成を保存…") { ensemble.savePanel() }.disabled(!ensemble.canEdit || composer.generating)
                Button("この編曲案を採用") {
                    if ensemble.dirty { confirmReplace = true } else { adopt() }
                }.buttonStyle(CabinetButton(primary: true))
                    .disabled(composer.candidate == nil || composer.generating || !ensemble.canEdit)
            }.padding(14)
        }.frame(width: 920, height: 690).background(Color(red: 0.10, green: 0.12, blue: 0.095))
            .buttonStyle(CabinetButton()).preferredColorScheme(.dark)
            .onChange(of: connection.provider) { _, _ in composer.cancel() }
            .onChange(of: connection.model) { _, _ in composer.cancel() }
            .onChange(of: connection.executable) { _, _ in composer.cancel() }
            .onDisappear { composer.cancel() }
            .confirmationDialog("未保存の構成を置き換えますか？", isPresented: $confirmReplace) {
                Button("編曲案で置き換える", role: .destructive) { adopt() }
                Button("キャンセル", role: .cancel) { }
            } message: { Text("全セクション・クリップ配置・テンポ・パート音量を置き換え、音符編集の履歴を消去します。元を残す場合はキャンセルして「現在の構成を保存…」を使ってください。") }
    }
    @ViewBuilder private var connectionSettings: some View {
        Group {
            switch connection.provider {
            case .codex:
                HStack {
                    TextField("Codexの実行ファイル", text: $connection.executable).textFieldStyle(.roundedBorder)
                    Button("選択…") { connection.browseCodex() }
                }
                Text("ログイン済みCodexの既定モデルを使用。指示・パート名・基準音・音符・配置を送信します。音声や元ファイルのパスは送りません。")
            case .openai:
                HStack {
                    SecureField("OpenAI APIキー・終了までメモリ内のみ", text: $connection.apiKey).textFieldStyle(.roundedBorder)
                    TextField("モデル", text: $connection.model).textFieldStyle(.roundedBorder).frame(width: 180)
                }
                Text("OpenAIへ指示・パート名・基準音・音符・配置を送信します。音声や元ファイルのパスは送信せず、API利用料は別途発生します。")
            case .external:
                HStack {
                    Text("指示と形式を他のAIへ渡し、返ってきた編曲JSONを貼り付けてください。")
                    Spacer()
                    Button("指示をコピー") { composer.copyBrief(ensemble: ensemble) }
                }
            case .demo:
                Text("接続不要の固定デモです。薄いイントロ→厚いサビ、または均一な構成を作ります。AIは呼びません。")
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary).disabled(composer.generating)
    }
    private func adopt() {
        if composer.adopt(ensemble: ensemble) { dismiss() }
    }
}

private struct ArrangementPreview: View {
    let snapshot: EnsembleSnapshot
    private func width(_ section: EnsembleSection) -> Double { max(110, section.beats * 12) }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text("提案された構成").font(.system(size: 10)).frame(width: 135)
                    ForEach(snapshot.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.name).font(.system(size: 12, weight: .semibold))
                            Text("\(section.beats.formatted()) 拍").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(width: width(section), height: 42).background(.white.opacity(0.08))
                    }
                }
                ForEach(snapshot.parts.indices, id: \.self) { index in
                    let part = snapshot.parts[index]
                    HStack(spacing: 2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(part.name).lineLimit(2)
                            Text("\(part.gainDB.formatted()) dB · \(part.muted ? "消音" : "発音")").foregroundStyle(.secondary)
                        }.font(.system(size: 11)).frame(width: 125, alignment: .leading).padding(.horizontal, 5)
                        ForEach(snapshot.sections) { section in
                            GeometryReader { geometry in
                                ForEach(part.allClips.filter { $0.sectionID == section.id }) { clip in
                                    let length = EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount) ?? 0
                                    VStack(spacing: 1) {
                                        Text("\(clip.performance.notes.count) 音符 ×\(clip.repeatCount) @\(clip.startBeat.formatted())")
                                            .font(.system(size: 9)).lineLimit(1)
                                        PerformanceNoteView(performance: clip.performance, repeatCount: clip.repeatCount, root: part.instrument.root)
                                    }.padding(3).frame(width: max(2, length / section.beats * geometry.size.width), height: 53)
                                        .background(Color(red: 0.31, green: 0.35, blue: 0.23).opacity(part.muted ? 0.35 : 0.9))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .offset(x: clip.startBeat / section.beats * geometry.size.width, y: 3)
                                        .help("\(clip.performance.name) · \(clip.performance.notes.count) 音符・\(clip.repeatCount)回・区切り内の開始拍 \(clip.startBeat.formatted())")
                                }
                            }.frame(width: width(section), height: 60).background(.black.opacity(0.2))
                        }
                    }.accessibilityElement(children: .combine)
                        .accessibilityLabel("提案パート \(part.name)・\(part.allClips.count)クリップ・\(part.gainDB.formatted())デシベル・\(part.muted ? "消音" : "発音")")
                }
            }.padding(6)
        }.background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("Proposed arrangement timeline").accessibilityLabel("提案された曲のタイムライン")
    }
}
