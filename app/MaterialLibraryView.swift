import SwiftUI

struct MaterialLibraryView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var library: MaterialLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saveExpanded = false
    @State private var confirmOpen = false
    @State private var openOriginal = false
    @State private var confirmAnnotations = false
    @State private var pendingAction: Action?
    private enum Action { case select(MaterialItem), close, open(Bool) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("保存した素材").font(.title2)
                Spacer()
                if model.adoptingSeparation { ProgressView().controlSize(.small); Text("音声と位置を確認中…").font(.caption) }
                Button("閉じる") { request(.close) }.disabled(library.busy || model.adoptingSeparation)
                    .accessibilityIdentifier("materials.close")
            }
            Text("名前・元曲名・タグ・メモで検索し、同じ区間を聴き比べられます。")
                .font(.callout).foregroundStyle(.secondary)
            saveSection
            HStack {
                TextField("素材名・曲名・タグ・メモを検索", text: $library.query)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("materials.search")
                Picker("タグ", selection: $library.tagID) {
                    Text("すべて").tag(String?.none)
                    ForEach(library.availableTags) { tag in Text(tag.name).tag(Optional(tag.id)) }
                }.frame(maxWidth: 220).accessibilityIdentifier("materials.tagFilter")
                if library.searching { ProgressView().controlSize(.small) }
            }.disabled(library.busy || model.adoptingSeparation)
            if library.busy {
                HStack { ProgressView().controlSize(.small); Button("処理を取り消す") { library.cancel() }.accessibilityIdentifier("materials.cancel") }
            }
            Text(library.message).font(.callout).accessibilityIdentifier("materials.status")
            if let error = library.error { Text(error).foregroundStyle(.red).textSelection(.enabled).lineLimit(3) }
            HStack(alignment: .top, spacing: 16) {
                VStack {
                    List(library.records, selection: Binding(get: { library.selected?.id }, set: { id in
                        if let item = library.records.first(where: { $0.id == id }), item.id != library.selected?.id { request(.select(item)) }
                    })) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.record.name)
                            Text(item.record.provenance.sourceName + " · " + item.record.location).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if !item.annotations.tags.isEmpty { Text(item.annotations.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.orange).lineLimit(1) }
                            if !item.annotations.note.isEmpty { Text(item.annotations.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }.padding(.vertical, 4).tag(item.id)
                    }.disabled(library.busy || library.searching || model.adoptingSeparation)
                    .overlay { if library.records.isEmpty && !library.searching { Text("該当する素材がありません").foregroundStyle(.secondary) } }
                    .accessibilityIdentifier("materials.list")
                    HStack {
                        Button("前へ") { library.page(-1) }.disabled(!library.canPrevious || library.busy).accessibilityIdentifier("materials.previous")
                        Text("\(library.total) 件 · \(library.total == 0 ? 0 : library.offset + 1)–\(library.offset + library.records.count)").font(.caption).accessibilityIdentifier("materials.count")
                        Button("次へ") { library.page(1) }.disabled(!library.canNext || library.busy).accessibilityIdentifier("materials.next")
                    }
                }.frame(minWidth: 260, maxWidth: .infinity)
                Divider()
                ScrollView {
                    if let selected = library.selected { details(selected) }
                    else { Text("素材を選ぶと、タグ・メモと比較試聴を表示します。").foregroundStyle(.secondary).padding(.top, 30) }
                }.frame(minWidth: 330, maxWidth: .infinity)
            }.frame(minHeight: 260, maxHeight: .infinity)
            HStack {
                Text("検索中も編集中のタグ・メモは保持します。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("元曲の位置を開く") { request(.open(true)) }.accessibilityIdentifier("materials.openOriginal")
                Button("パートと選択範囲を開く") { request(.open(false)) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("materials.open")
            }.disabled(library.selected == nil || model.busy || library.draft != nil)
        }.padding(24).frame(minWidth: 900, idealWidth: 1020, minHeight: 680, idealHeight: 760)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(library.busy || model.adoptingSeparation || library.annotationDirty)
        .task {
            model.stop(); model.library.stopPreview(); model.suspendMIDI(true)
            name = model.materialOrigin.map { $0.provenance.sourceName + " · " + $0.provenance.stem } ?? ""
            saveExpanded = model.materialOrigin != nil
            library.refresh()
        }
        .onDisappear { library.cancel(); model.suspendMIDI(model.ensembleWorkspaceActive) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in library.stopPreview() }
        .onExitCommand { if !model.busy { request(.close) } }
        .confirmationDialog("タグ・メモに未保存の変更があります", isPresented: $confirmAnnotations) {
            Button("保存して続ける") { library.saveAnnotations { if let action = pendingAction { pendingAction = nil; perform(action) } } }
            Button("変更を破棄して続ける", role: .destructive) {
                library.discardAnnotations()
                if let action = pendingAction { pendingAction = nil; perform(action) }
            }
            Button("戻る", role: .cancel) { pendingAction = nil }
        } message: { Text("変更を保存するか、破棄して次の操作へ進むか選んでください。") }
        .confirmationDialog("編集中の楽器に未保存の変更があります", isPresented: $confirmOpen) {
            Button("保存してから開く…") { Task { if await model.saveBeforeSeparationUse() { open() } } }
            Button("変更を破棄して開く", role: .destructive) { open() }
            Button("戻る", role: .cancel) {}
        } message: { Text("保存した素材の波形で、現在の楽器を置き換えます。") }
    }
    private var saveSection: some View {
        DisclosureGroup("現在の選択を保存", isExpanded: $saveExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let origin = model.materialOrigin {
                    Text("元曲: " + origin.provenance.sourceName).lineLimit(1).help(origin.provenance.sourceName)
                    Text(String(format: "%@ · %.3f–%.3f 秒", origin.provenance.stem, model.editor.selectionStart, model.editor.selectionEnd))
                        .monospacedDigit().accessibilityIdentifier("materials.selection")
                    HStack {
                        TextField("素材名", text: $name).accessibilityIdentifier("materials.name").disabled(library.busy || library.draft != nil)
                        if library.draft == nil {
                            Button("保存容量を確認") { model.prepareMaterial(name: name) }
                                .disabled(model.busy || !model.canSaveMaterial || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("materials.prepare")
                        }
                    }
                    if let draft = library.draft {
                        HStack {
                            Text("追加容量: " + ByteCountFormatter.string(fromByteCount: draft.additionalBytes, countStyle: .file)).accessibilityIdentifier("materials.capacity")
                            Spacer()
                            Button("保存する") { library.commit() }.buttonStyle(.borderedProminent).accessibilityIdentifier("materials.commit")
                            Button("準備を破棄") { library.cancel() }
                        }.disabled(library.busy)
                        Text("元入力・元曲・選択パートの全長と切片を含み、同じ音声は共有します。").font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.canSaveMaterial { Text("波形で30秒以内の範囲を選択してください。").font(.caption) }
                } else { Text("分離したパートを編集画面へ渡し、波形で範囲を選択してください。").foregroundStyle(.secondary) }
            }.padding(10)
        }.accessibilityIdentifier("materials.saveSection")
    }
    private func details(_ selected: MaterialItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected.record.name).font(.headline)
            Text(selected.record.provenance.sourceName + "\n" + selected.record.location).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("同じ区間を比較").font(.headline)
            HStack {
                ForEach(MaterialPreviewKind.allCases) { kind in
                    Button(library.previewKind == kind ? kind.name + "・試聴中" : kind.name) { model.previewMaterial(kind) }
                        .tint(library.previewKind == kind ? .orange : nil)
                        .accessibilityIdentifier("materials.preview." + kind.rawValue)
                }
                Button("停止") { library.stopPreview() }.accessibilityIdentifier("materials.preview.stop")
            }.disabled(model.busy)
            if library.previewLoading { HStack { ProgressView().controlSize(.small); Text("区間を準備中…").font(.caption) } }
            Slider(value: Binding(get: { library.previewPosition }, set: { library.seekPreview($0) }), in: 0...max(0.001, library.previewDuration))
                .disabled(library.previewDuration == 0).accessibilityIdentifier("materials.preview.seek").accessibilityLabel("比較区間内の再生位置・秒")
            Text(String(format: "%.3f / %.3f 秒 · %@", library.previewPosition, library.previewDuration, library.previewKind?.name ?? "停止中"))
                .font(.caption).monospacedDigit().accessibilityIdentifier("materials.preview.status")
            Text("−14 dBで試聴。切り替えは同じ位置から、同じボタンでもう一度押すと先頭から。選択区間の外は再生しません。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("タグ（カンマ区切り・20個まで）").font(.caption)
            TextField("例: ドラム, 硬い, 短い", text: $library.tagsText).accessibilityIdentifier("materials.tags")
            Text("メモ（4000文字まで）").font(.caption)
            TextEditor(text: $library.noteText).frame(height: 90).overlay { Rectangle().stroke(.secondary.opacity(0.3)) }.accessibilityIdentifier("materials.note")
            HStack {
                Button("タグ・メモを保存") { library.saveAnnotations() }.disabled(!library.annotationDirty).accessibilityIdentifier("materials.annotations.save")
                Button("変更を戻す") { library.discardAnnotations() }.disabled(!library.annotationDirty).accessibilityIdentifier("materials.annotations.discard")
                if library.annotationDirty { Text("未保存").font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.trailing, 4).disabled(library.busy || model.adoptingSeparation)
    }
    private func request(_ action: Action) {
        if library.annotationDirty { pendingAction = action; confirmAnnotations = true } else { perform(action) }
    }
    private func perform(_ action: Action) {
        switch action {
        case .select(let item): _ = library.select(item, discardEdits: true)
        case .close: library.cancel(); dismiss()
        case .open(let original):
            openOriginal = original
            if model.instrumentDirty { confirmOpen = true } else { open() }
        }
    }
    private func open() {
        guard let selected = library.selected else { return }
        model.stop(); model.library.stopPreview()
        Task { if await model.openMaterial(selected.id, original: openOriginal) { dismiss() } }
    }
}
