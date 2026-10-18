import SwiftUI

struct EnsembleView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmOpen = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent)
                Text("曲の構成").font(.system(size: 22, weight: .medium))
                Text("\(ensemble.parts.count) / 4 パート").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(ensemble.dirty ? "● 未保存" : ensemble.fileURL == nil ? "新規" : "保存済み")
                    .font(.system(size: 11)).foregroundStyle(ensemble.dirty ? accent : .secondary)
                Spacer()
                if ensemble.busy { ProgressView().controlSize(.small) }
                Button("開く…") { if ensemble.dirty { confirmOpen = true } else { ensemble.openPanel() } }
                    .buttonStyle(StudioButton()).disabled(!ensemble.canEdit).accessibilityIdentifier("Open ensemble").accessibilityLabel("構成を開く")
                Button("保存…") { ensemble.savePanel() }.buttonStyle(StudioButton())
                    .disabled(!ensemble.canEdit || ensemble.parts.isEmpty).accessibilityIdentifier("Save ensemble").accessibilityLabel("構成を保存")
                Button("WAV書き出し…") { ensemble.exportPanel(protecting: model.asset.map { [$0.url] } ?? []) }
                    .buttonStyle(StudioButton()).disabled(!ensemble.canEdit || ensemble.parts.isEmpty)
                Button("閉じる") { ensemble.stop(); dismiss() }.buttonStyle(StudioButton()).disabled(ensemble.exporting)
            }
            HStack {
                Button("パート追加") { ensemble.addPart() }
                Button("編集中の楽器を追加") {
                    if let instrument = currentInstrument {
                        ensemble.addPart(instrument: instrument, performance: model.midi.performance)
                    }
                }.disabled(model.instrumentSample == nil || model.busy)
                Spacer()
                Button("繰り返しデモ") { Task { await ensemble.addDemos(staggered: true, repeating: true) } }.disabled(ensemble.parts.count > 2)
                Button("4拍遅れて入るデモ") { Task { await ensemble.addDemos(staggered: true) } }.disabled(ensemble.parts.count > 2)
                Button("デモ2パート") { Task { await ensemble.addDemos() } }.disabled(ensemble.parts.count > 2)
            }.buttonStyle(StudioButton()).disabled(!ensemble.canEdit || ensemble.parts.count >= 4)
            Text(JapaneseUI.status(ensemble.fileMessage ?? ensemble.fileURL?.lastPathComponent ?? "無題の構成・制作を続けるために保存してください"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Button("曲の編集を取り消す") { ensemble.restoreSongEdit() }.disabled(!ensemble.canUndoSong)
                    .accessibilityIdentifier("Undo song edit").help(ensemble.undoSongLabel)
                Button("曲の編集をやり直す") { ensemble.restoreSongEdit(redo: true) }.disabled(!ensemble.canRedoSong)
                    .accessibilityIdentifier("Redo song edit").help(ensemble.redoSongLabel)
            }.buttonStyle(StudioButton())
            EnsembleSectionsView(ensemble: ensemble)
            if ensemble.parts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "pianokeys").font(.system(size: 36)).foregroundStyle(accent)
                    Text("複数の楽器で曲を作る").font(.system(size: 18, weight: .medium))
                    Text("各パートに楽器と演奏を割り当てるか、デモ2パートで試せます。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EnsembleTimelineView(ensemble: ensemble)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ensemble.parts) { part in
                            EnsemblePartRow(part: part, ensemble: ensemble, library: library,
                                            currentPerformance: model.midi.performance)
                        }
                    }.padding(.vertical, 2)
                }
            }
            Divider()
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("テンポ").font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack {
                        TextField("曲全体のテンポ", value: $ensemble.tempo, format: .number).frame(width: 55).textFieldStyle(.roundedBorder)
                        Text("BPM").foregroundStyle(.secondary)
                    }.font(.system(size: 12)).disabled(!ensemble.canEdit)
                }
                Button(ensemble.playing ? "全停止" : "全体を再生") {
                    if ensemble.playing { ensemble.stop() }
                    else { model.stop(); ensemble.play() }
                }.buttonStyle(StudioButton(primary: true)).disabled(ensemble.busy || ensemble.parts.isEmpty)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ensemble.playing ? (ensemble.releasing ? "余韻を再生中…" : String(format: "再生位置 %.1f / %.1f 拍", ensemble.positionBeats, ensemble.durationBeats)) : "準備完了・共通テンポ")
                    ProgressView(value: ensemble.positionBeats, total: max(1, ensemble.durationBeats)).tint(accent)
                }.font(.system(size: 11)).frame(width: 200)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "全体音量・%.0f dB", ensemble.masterDB)).font(.system(size: 10))
                    Slider(value: $ensemble.masterDB, in: -60...0).frame(width: 130).tint(accent).accessibilityIdentifier("Ensemble master volume").accessibilityLabel("曲全体の音量").disabled(ensemble.busy)
                    Text("出力 \(Int(ensemble.level)) dB").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if ensemble.exporting {
                HStack {
                    ProgressView(value: ensemble.exportProgress).tint(accent)
                    Text("書き出し中 \(Int(ensemble.exportProgress * 100))%").font(.system(size: 11)).monospacedDigit()
                    Button("書き出しを中止") { ensemble.cancelExport() }.buttonStyle(StudioButton())
                }
            }
            if let error = ensemble.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3).help(error) }
            Text("保存すると楽器・演奏・開始拍・音量・テンポをまとめて残せます。起動時は最後に保存または開いた構成を復元します。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 880, height: 760)
            .background(Color(red: 0.075, green: 0.09, blue: 0.105)).preferredColorScheme(.dark)
            .confirmationDialog("未保存の構成を置き換えますか？", isPresented: $confirmOpen) {
                Button("構成を選ぶ…", role: .destructive) { ensemble.openPanel() }
                Button("キャンセル", role: .cancel) { }
            } message: { Text("変更を残す場合はキャンセルして先に保存してください。読み込みに失敗した場合は元の構成を保ちます。") }
            .onDisappear { ensemble.stop() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in ensemble.stop() }
    }
    private var currentInstrument: EnsembleInstrument? {
        guard let sample = model.instrumentSample else { return nil }
        return EnsembleInstrument(sample: sample, root: model.rootNote, envelope: model.envelope,
                                  loop: model.sampleLoop, name: model.instrumentFileURL?.deletingPathExtension().lastPathComponent ?? sample.name)
    }
}

private struct EnsemblePartRow: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    let currentPerformance: PerformanceDocument
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("パート名", text: $part.name).font(.system(size: 14, weight: .medium)).textFieldStyle(.plain)
                    .disabled(!ensemble.canEdit)
                Picker("Section for \(part.name)", selection: $part.sectionID) {
                    Text("曲の先頭から").tag(Optional<UUID>.none)
                    ForEach(ensemble.sections) { section in Text(section.name).tag(Optional(section.id)) }
                }.labelsHidden().frame(width: 145).disabled(!ensemble.canEdit)
                Spacer()
                Text("\(part.voices)/8音").font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.black.opacity(0.3))
                        Rectangle().fill(accent).frame(width: geometry.size.width * CGFloat(max(0, min(1, (part.level + 60) / 60))))
                    }
                }.frame(width: 70, height: 5).accessibilityIdentifier("\(part.name) output \(Int(part.level)) decibels").accessibilityLabel("\(part.name) の出力 \(Int(part.level)) デシベル")
                Button("削除") { ensemble.remove(part.id) }.disabled(!ensemble.canEdit)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("楽器").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack {
                        Picker("Instrument for \(part.name)", selection: Binding<URL?>(get: { part.instrumentURL }, set: { url in
                            if let url { Task { await ensemble.loadInstrument(url, part: part.id) } }
                        })) {
                            Text(part.instrumentURL == nil ? (part.instrument?.name ?? "楽器を選択") : "楽器を選択")
                                .tag(Optional<URL>.none)
                            ForEach(library.entries) { entry in
                                Text(entry.name + (entry.available ? "" : " · Missing")).tag(Optional(entry.url))
                            }
                            if let url = part.instrumentURL, !library.entries.contains(where: { $0.url == url }) {
                                Text(part.instrument?.name ?? url.lastPathComponent).tag(Optional(url))
                            }
                        }.labelsHidden().frame(width: 220)
                        Button("開く…") { ensemble.openInstrument(part.id) }.accessibilityIdentifier("Open instrument for \(part.name)").accessibilityLabel("楽器を開く \(part.name)")
                    }
                    Text(part.instrument.map { "基準音 \(NotePitch.name($0.root)) · \($0.loop.enabled ? "ループ" : "一度だけ再生")" } ?? "一覧から選ぶか、保存した楽器を開いてください")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(width: 300, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text("演奏データ").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack {
                        Text(part.performance.name).font(.system(size: 12)).lineLimit(1).frame(width: 180, alignment: .leading)
                        Menu("プリセット") {
                            ForEach(MIDIPerformancePreset.allCases) { preset in
                                Button(JapaneseUI.preset(preset)) { ensemble.setPerformance(.preset(preset), part: part.id) }
                            }
                        }.frame(width: 65)
                        Button("開く…") { ensemble.openPerformance(part.id) }.accessibilityIdentifier("Open performance for \(part.name)").accessibilityLabel("演奏を開く \(part.name)")
                        Button("編集中の演奏を使う") { ensemble.setPerformance(currentPerformance, part: part.id) }
                            .help("素材編集画面の演奏をコピーします。AIで作った演奏も使えます。")
                    }
                    Text("\(part.performance.notes.count) 音符・Follows ensemble tempo")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.disabled(!ensemble.canEdit)
            HStack {
                Text("開始").foregroundStyle(.secondary)
                TextField("開始拍", value: $part.startBeat, format: .number).frame(width: 48).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("Start beat for \(part.name)").accessibilityLabel("開始拍 \(part.name)").disabled(!ensemble.canEdit)
                Stepper("", value: $part.startBeat, in: 0...256, step: 1).labelsHidden().disabled(!ensemble.canEdit)
                Text("拍").foregroundStyle(.secondary)
                Text("繰り返し").foregroundStyle(.secondary)
                Stepper(value: $part.repeatCount, in: 1...16) {
                    Text("×\(part.repeatCount)").monospacedDigit().frame(width: 28)
                }.frame(width: 70).accessibilityIdentifier("Repeat count for \(part.name)").accessibilityLabel("繰り返し回数 \(part.name)").disabled(!ensemble.canEdit)
                Toggle("消音", isOn: $part.muted).toggleStyle(.checkbox)
                Slider(value: $part.gainDB, in: -36...0).frame(width: 145).tint(accent).accessibilityIdentifier("\(part.name) volume").accessibilityLabel("\(part.name) の音量")
                Text(String(format: "%.0f dB", part.gainDB)).monospacedDigit().frame(width: 40)
                Spacer()
                Text(validation ?? "準備完了").foregroundStyle(validation == nil ? Color.secondary : .orange).lineLimit(1)
            }.disabled(ensemble.busy).font(.system(size: 10))
            HStack {
                Text("演奏クリップ・\(part.allClips.count) / 8・音色と音量は共通")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                EnsembleDuplicateMenu(part: part, ensemble: ensemble, clip: part.allClips[0])
                Menu("演奏クリップ追加") {
                    ForEach(ensemble.sections) { section in
                        Button(section.name) { ensemble.addClip(part: part.id, sectionID: section.id) }
                    }
                    Button("曲の先頭から") { ensemble.addClip(part: part.id, sectionID: nil) }
                }.frame(width: 140).disabled(!ensemble.canEdit || part.additionalClips.count >= 7)
                    .accessibilityIdentifier("Add section clip for \(part.name)").accessibilityLabel("演奏クリップを追加 \(part.name)")
            }
            ForEach(part.additionalClips) { clip in
                EnsembleClipEditor(part: part, ensemble: ensemble, clip: clip, currentPerformance: currentPerformance)
            }
        }.controlSize(.small).padding(14)
            .background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)) }
    }
    private var validation: String? {
        guard let instrument = part.instrument else { return "Assign an instrument" }
        guard part.startBeat.isFinite, (0...256).contains(part.startBeat) else { return "Start: 0–256 beats" }
        guard (1...16).contains(part.repeatCount) else { return "Repeat: 1–16" }
        do {
            try EnsembleSections.validate(ensemble.sections)
            try EnsembleClips.validate(part.allClips, root: instrument.root, sections: ensemble.sections); return nil
        }
        catch { return error.localizedDescription }
    }
}
