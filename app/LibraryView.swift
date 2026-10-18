import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var library: InstrumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var confirmLoad = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var selected: LibraryEntry? { library.filtered.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up").foregroundStyle(accent)
                Text("楽器ライブラリ").font(.system(size: 22, weight: .medium))
                Spacer()
                if library.busy || model.busy { ProgressView().controlSize(.small) }
                Button("閉じる") { dismiss() }.buttonStyle(StudioButton())
            }
            HStack {
                TextField("楽器を検索", text: $library.query).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("Search instruments").accessibilityLabel("楽器を検索")
                Button("楽器ファイルを追加") { library.addPanel() }.buttonStyle(StudioButton())
                Button("デモ楽器追加") { Task { await library.addDemos() } }.buttonStyle(StudioButton())
            }.disabled(library.busy || model.busy)
            HStack {
                Text("\(library.filtered.count) \(library.filtered.count == 1 ? "楽器" : "楽器")").foregroundStyle(.secondary)
                Spacer()
                Text("保存した楽器・元の保存場所").foregroundStyle(.secondary)
            }.font(.system(size: 11))
            if library.filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "pianokeys").font(.system(size: 32)).foregroundStyle(accent)
                    Text(library.entries.isEmpty ? "楽器を一覧にまとめる" : "一致する楽器がありません")
                    Text(library.entries.isEmpty ? "保存済みの楽器を追加するか、デモ楽器で試せます。" : "別の名前で検索してください。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(library.filtered, selection: $selection) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name).font(.system(size: 13, weight: .medium))
                            Text(entry.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(entry.available ? (library.previewing == entry.url ? "試聴中" : "準備完了") : "見つかりません")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(entry.available ? accent : .secondary)
                    }.padding(.vertical, 8).tag(entry.id)
                }.scrollContentBackground(.hidden).background(.black.opacity(0.15))
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.previewing == nil ? "楽器を選んで試聴・読み込み" : "試聴中・−18 dB")
                    Text(library.previewDescription.map(JapaneseUI.preview) ?? "試聴は編集中の楽器や変更を保ちます。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.font(.system(size: 12))
                Spacer()
                Button(library.previewing == nil ? "試聴" : "試聴停止") {
                    if library.previewing != nil { library.stopPreview() }
                    else if let selected { model.stop(); Task { await library.preview(selected) } }
                }.buttonStyle(StudioButton())
                    .disabled(library.busy || model.busy || (library.previewing == nil && selected?.available != true))
                Button("楽器を読み込む") {
                    if model.instrumentDirty { confirmLoad = true } else { loadSelected() }
                }.buttonStyle(StudioButton(primary: true))
                    .disabled(selected?.available != true || library.busy || model.busy)
            }
            HStack {
                if let selected {
                    Button("一覧から外す") { library.remove(selected); selection = nil }.buttonStyle(.plain)
                        .disabled(library.busy || model.busy)
                    Text("元のファイルは保持します。").foregroundStyle(.secondary)
                }
                Spacer()
            }.font(.system(size: 10))
            if let error = library.error ?? model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3).help(error)
            }
        }.padding(24).frame(width: 780, height: 570)
            .background(Color(red: 0.075, green: 0.09, blue: 0.105)).preferredColorScheme(.dark)
            .confirmationDialog("未保存の楽器を置き換えますか？", isPresented: $confirmLoad) {
                Button("楽器を置き換える", role: .destructive) { loadSelected() }
                Button("キャンセル", role: .cancel) { }
            } message: { Text("編集中の楽器に未保存の変更があります。残す場合はキャンセルして先に保存してください。") }
            .onChange(of: selection) { _, _ in library.stopPreview() }
            .onChange(of: library.query) { _, _ in selection = nil; library.stopPreview() }
            .onDisappear { library.stopPreview() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in library.stopPreview() }
    }
    private func loadSelected() {
        guard let selected else { return }
        library.stopPreview()
        Task { if await model.loadInstrument(selected.url) { dismiss() } }
    }
}
