import SwiftUI
import AppKit

struct SeparationView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var separation: SeparationModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String? = "drums"
    @State private var confirmUse = false
    @State private var adopting = false
    @State private var showSettings = false
    private var entry: SeparationAudio? { separation.audio.first { $0.id == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("曲から音を取り出す").font(.title2)
                Spacer()
                Button("閉じる") { separation.cancel(); separation.stopPreview(); dismiss() }.accessibilityIdentifier("separation.close")
                    .disabled(adopting)
            }
            Text("ドラム・ベース・ボーカル・その他の楽器に分けます。取り出した音を聴いて、使う部分を波形で選びます。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("曲を選んで分離…") { separation.chooseSource { model.stop(); model.library.stopPreview(); model.ensemble.stop() } }
                    .accessibilityIdentifier("separation.choose").disabled(separation.busy || adopting)
                if separation.busy {
                    ProgressView().controlSize(.small)
                    Button("処理を取り消す") { separation.cancel() }.accessibilityIdentifier("separation.cancel")
                }
                Spacer()
                Button(showSettings ? "設定を閉じる" : "実行環境の設定") { showSettings.toggle() }
            }
            if showSettings {
                VStack(alignment: .leading, spacing: 8) {
                    Text("このMacの専用Python環境を使います。モデルの準備時だけダウンロードし、曲は外部へ送りません。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack { Text("Python").frame(width: 60, alignment: .leading); TextField("専用venvのbin/python", text: $separation.pythonPath); Button("選択…") { separation.choosePython() } }
                    HStack { Text("モデル").frame(width: 60, alignment: .leading); TextField("保存フォルダ", text: $separation.cachePath); Button("選択…") { separation.chooseCache() } }
                    Button("モデルを準備") { model.stop(); model.library.stopPreview(); separation.start(source: nil) }
                        .accessibilityIdentifier("separation.prepare")
                    Text("必要な固定版とセットアップ方法は OPERATIONS.md の「音源分離」を参照してください。")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(separation.busy || adopting)
            }
            Text(separation.status).font(.callout).accessibilityIdentifier("separation.status")
            if let error = separation.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if !separation.sourceName.isEmpty { Text(separation.sourceName).font(.caption).lineLimit(1) }
            List(separation.audio, selection: $selected) { audio in
                HStack {
                    Image(systemName: audio.id == "original" ? "music.note" : "waveform")
                    Text(audio.name)
                    Spacer()
                    Text(separation.previewID == audio.id ? "試聴中" : timeLabel(Double(audio.frames) / audio.sampleRate)).foregroundStyle(.secondary)
                }.padding(.vertical, 6).tag(audio.id)
            }.frame(minHeight: 150)
            .disabled(separation.busy || adopting)
            HStack {
                Button("選んだ音を試聴") {
                    guard let entry else { return }; model.stop(); model.library.stopPreview(); model.ensemble.stop(); separation.preview(entry)
                }.accessibilityIdentifier("separation.preview").disabled(entry == nil || separation.busy || adopting)
                Button("試聴停止") { separation.stopPreview() }.accessibilityIdentifier("separation.stopPreview")
                Slider(value: Binding(get: { separation.previewPosition }, set: { separation.seekPreview($0) }), in: 0...max(1, separation.previewDuration))
                    .accessibilityIdentifier("separation.seek").accessibilityLabel("試聴位置・秒")
                    .disabled(separation.previewDuration == 0)
                Text(timeLabel(separation.previewPosition)).monospacedDigit()
            }
            HStack {
                Text("試聴は−14 dB。音を切り替えると同じ時刻から聴けます。\nその他にはギターや鍵盤などが混ざる場合があります。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("この音を編集") {
                    if model.instrumentDirty { confirmUse = true }
                    else { useSelection() }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("separation.use")
                    .disabled(entry == nil || separation.busy || adopting || model.busy)
            }
            Text("編集画面で30秒以内の範囲を選択 →「選択を楽器に」→ 基準音・余韻を調整 →「保存…」")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 760, idealWidth: 820, minHeight: 540)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(separation.busy || adopting)
        .confirmationDialog("編集中の楽器に未保存の変更があります", isPresented: $confirmUse) {
            Button("保存してから使う…") { Task { if await model.saveBeforeSeparationUse() { useSelection() } } }
            Button("変更を破棄して使う", role: .destructive) { useSelection() }
            Button("戻る", role: .cancel) {}
        } message: { Text("現在の楽器を置き換えて、選んだ音の波形を開きます。曲の構成は保持します。") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in separation.stopPreview() }
        .onDisappear { separation.cancel(); separation.stopPreview() }
    }
    private func useSelection() {
        guard let entry, let url = separation.url(for: entry) else { return }
        separation.stopPreview(); adopting = true
        Task {
            let success = await model.useSeparatedAudio(url, origin: separation.origin(for: entry))
            adopting = false
            if success { dismiss() }
        }
    }
}
