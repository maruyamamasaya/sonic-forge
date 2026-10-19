import SwiftUI

struct MaterialLibraryView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var library: MaterialLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saveExpanded = false
    @State private var confirmOpen = false
    @State private var openOriginal = false
    @State private var openClip = false
    @State private var confirmAnnotations = false
    @State private var pendingAction: Action?
    private enum Action { case select(MaterialItem), close, open(Bool), reedit, parent(String), scope(Bool), trash, delete, protections, batchDelete }
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
            HStack {
                Button("素材一覧") { request(.scope(false)) }.disabled(!library.showingTrash)
                    .accessibilityIdentifier("materials.active")
                Button("ゴミ箱") { request(.scope(true)) }.disabled(library.showingTrash)
                    .accessibilityIdentifier("materials.trash")
                if !library.pendingReclaims.isEmpty {
                    Menu("未回収音声（\(library.pendingReclaims.count)件）") {
                        ForEach(library.pendingReclaims) { item in
                            Button(item.record.name) { request(.select(item)) }
                        }
                    }.accessibilityIdentifier("materials.delete.pending")
                }
                if !library.protectedDeleted.isEmpty {
                    Menu("削除済み素材の来歴") {
                        ForEach(library.protectedDeleted) { item in Button(item.record.name) { request(.select(item)) } }
                    }.accessibilityIdentifier("materials.protection.deleted")
                }
                Text(library.showingTrash ? "ゴミ箱 · 復元できます" : "保存した素材")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(model.busy || library.draft != nil)
            if !library.showingTrash { saveSection }
            if library.showingTrash {
                HStack {
                    Button("このページを全選択") { library.selectPageForDeletion(true) }.accessibilityIdentifier("materials.batch.selectPage")
                    Button("選択を解除") { library.selectPageForDeletion(false) }.accessibilityIdentifier("materials.batch.clear")
                    Text("削除対象 \(library.deletionSelection.count) 件").font(.caption).accessibilityIdentifier("materials.batch.count")
                    Spacer()
                    Button("選択した素材の完全削除を確認…") { request(.batchDelete) }
                        .disabled(library.deletionSelection.isEmpty || library.draft != nil).accessibilityIdentifier("materials.batch.review")
                }.disabled(library.busy || library.searching || model.adoptingSeparation)
                Text("対象のチェックは詳細表示の選択とは別です。検索・タグ・ページ・表示の変更でチェックを解除します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                            HStack {
                                if library.showingTrash {
                                    Toggle("削除対象", isOn: Binding(get: { library.deletionSelection.contains(item.id) }, set: { library.setDeletionSelected(item.id, selected: $0) }))
                                        .toggleStyle(.checkbox).labelsHidden().accessibilityLabel("削除対象: " + item.record.name)
                                        .accessibilityIdentifier("materials.batch.item." + item.id)
                                }
                                Text(item.record.name)
                            }
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
                    if let selected = library.selected {
                        if selected.deletedAt != nil { deletedDetails(selected) } else { details(selected) }
                    }
                    else { Text("素材を選ぶと、タグ・メモと比較試聴を表示します。").foregroundStyle(.secondary).padding(.top, 30) }
                }.frame(minWidth: 330, maxWidth: .infinity)
            }.frame(minHeight: 260, maxHeight: .infinity)
            HStack {
                Text("検索中も編集中のタグ・メモは保持します。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("素材だけを再編集") { request(.reedit) }.accessibilityIdentifier("materials.reedit")
                Button("元曲の位置を開く") { request(.open(true)) }.accessibilityIdentifier("materials.openOriginal")
                Button("パートと選択範囲を開く") { request(.open(false)) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("materials.open")
            }.disabled(library.selected == nil || library.selected?.trashedAt != nil || library.selected?.deletedAt != nil || model.busy || library.draft != nil)
        }.padding(24).frame(minWidth: 900, idealWidth: 1020, minHeight: 680, idealHeight: 760)
        .preferredColorScheme(.dark)
        .sheet(item: Binding(get: { library.deletionPlan }, set: { if $0 == nil { library.dismissDeletion() } })) { plan in
            MaterialDeletionReview(plan: plan, busy: library.busy, cancel: { library.dismissDeletion() }) {
                model.stop()
                library.confirmDeletion(protections: model.materialDeletionProtections, files: model.materialDeletionFiles)
            }
        }
        .sheet(item: $library.protectionReview, onDismiss: { library.releasePlan = nil }) { review in
            protectionSheet(review)
        }
        .interactiveDismissDisabled(library.busy || model.adoptingSeparation || library.annotationDirty)
        .task {
            model.stop(); model.library.stopPreview(); model.suspendMIDI(true)
            name = model.materialOrigin.map { $0.provenance.sourceName + " · " + $0.provenance.stem } ?? ""
            saveExpanded = model.materialOrigin != nil
            library.refresh()
            if let id = model.revealMaterialID {
                model.revealMaterialID = nil
                await library.reveal(id)
            }
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
                    if let selection = model.materialSelectionInSource {
                        Text(String(format: "元曲上: %@ · %.3f–%.3f 秒", origin.provenance.stem,
                            Double(selection.startFrame) / origin.provenance.sampleRate,
                            Double(selection.endFrame) / origin.provenance.sampleRate))
                            .monospacedDigit().accessibilityIdentifier("materials.selection")
                    } else {
                        Text("元曲上の範囲: 波形で範囲を選択してください。")
                            .accessibilityIdentifier("materials.selection")
                    }
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
                } else if model.waveformProvenance != nil {
                    Text("元曲の管理音声を確認できません。来歴付きの楽器保存は可能です。").foregroundStyle(.secondary)
                } else { Text("分離したパートを編集画面へ渡し、波形で範囲を選択してください。").foregroundStyle(.secondary) }
            }.padding(10)
        }.accessibilityIdentifier("materials.saveSection")
    }
    private func details(_ selected: MaterialItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected.record.name).font(.headline)
            Button("参照・保護記録を確認…") { request(.protections) }
                .disabled(library.draft != nil).accessibilityIdentifier("materials.protection.review")
            if selected.trashedAt != nil {
                Button("完全削除の影響を確認…") { request(.delete) }
                    .disabled(library.draft != nil).accessibilityIdentifier("materials.delete.review")
            }
            if let date = selected.trashedAt {
                Text("ゴミ箱へ移動: " + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).accessibilityIdentifier("materials.trashedAt")
            }
            Button(selected.trashedAt == nil ? "ゴミ箱へ移動" : "素材を復元") { request(.trash) }
                .disabled(library.draft != nil)
                .accessibilityIdentifier(selected.trashedAt == nil ? "materials.moveToTrash" : "materials.restore")
            Text("音声と来歴は保持します。他の素材や楽器は引き続き使えます。")
                .font(.caption).foregroundStyle(.secondary)
            if let parent = selected.record.parentMaterialID {
                Button("親素材を確認") { request(.parent(parent)) }
                    .disabled(library.draft != nil).accessibilityIdentifier("materials.parent")
            }
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
    private func deletedDetails(_ selected: MaterialItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected.record.name).font(.headline)
            Button("参照・保護記録を確認…") { request(.protections) }
                .disabled(library.draft != nil).accessibilityIdentifier("materials.protection.review")
            Text("完全削除済み · 来歴の参照記録").accessibilityIdentifier("materials.deleted")
            Text(selected.record.provenance.sourceName + "\n" + selected.record.location).textSelection(.enabled)
            Text("素材の復元はできません。楽器や派生素材が使う来歴の記録を残しています。")
                .foregroundStyle(.secondary)
            if let parent = selected.record.parentMaterialID {
                Button("親素材を確認") { request(.parent(parent)) }.accessibilityIdentifier("materials.parent")
            }
            HStack {
                ForEach(MaterialPreviewKind.allCases) { kind in
                    Button(kind.name) { model.previewMaterial(kind) }.accessibilityIdentifier("materials.preview." + kind.rawValue)
                }
                Button("停止") { library.stopPreview() }.accessibilityIdentifier("materials.preview.stop")
            }.disabled(model.busy)
            Text("保護音声が残っている場合は比較試聴できます。回収済みの場合は来歴のみ参照できます。")
                .font(.caption).foregroundStyle(.secondary)
            Button("未回収音声を再確認…") { request(.delete) }.accessibilityIdentifier("materials.delete.retry")
        }.font(.callout).disabled(library.busy || model.adoptingSeparation)
    }
    private func protectionSheet(_ review: MaterialStore.ProtectionReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("参照・保護記録").font(.title2)
            Text("登録済みファイル、現在の楽器・構成と履歴を確認します。過去の保護記録は実在するファイルの一覧とは限りません。")
                .font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(review.references, id: \.self) { Text($0).textSelection(.enabled) }
                    if review.references.isEmpty { Text("参照はありません。") }
                    Divider()
                    Text("永続保護記録").font(.headline)
                    ForEach(review.entries) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.label)
                                Text(entry.materialID).font(.caption2).textSelection(.enabled)
                            }
                            Spacer()
                            Button("解除の影響を確認") {
                                library.reviewRelease(entry, protections: model.materialDeletionProtections, files: model.materialDeletionFiles)
                            }.accessibilityIdentifier("materials.protection.prepare")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: library.releasePlan == nil ? 300 : 180)
            if let plan = library.releasePlan {
                Divider()
                Text("解除対象: " + plan.entry.label).font(.headline)
                Text("この素材・削除済み祖先で新たに回収可能: " + ByteCountFormatter.string(fromByteCount: max(0, plan.after.bytes - plan.before.bytes), countStyle: .file))
                    .accessibilityIdentifier("materials.protection.capacity")
                Text("解除後に残る参照: " + plan.after.references.joined(separator: "、")).font(.caption).lineLimit(3)
                Text(plan.blocked ? "現在使用中、または登録済みファイルが参照しています。閉じる・登録解除などで使用を終えてから再確認してください。" : "この記録だけを解除します。素材・来歴・外部ファイルは残します。削除済み素材の管理音声は後で回収でき、回収後は比較・再編集できなくなる場合があります。再使用すると保護を再登録します。")
                    .font(.callout)
                HStack {
                    Button("解除せず戻る") { library.releasePlan = nil }
                    Button("保護記録を解除", role: .destructive) {
                        library.confirmRelease(protections: model.materialDeletionProtections, files: model.materialDeletionFiles)
                    }.disabled(plan.blocked).accessibilityIdentifier("materials.protection.confirm")
                }
            }
            if let error = library.error { Text(error).foregroundStyle(.red).lineLimit(3) }
            if library.busy { ProgressView() }
            HStack { Spacer(); Button("閉じる") { library.releasePlan = nil; library.protectionReview = nil }.accessibilityIdentifier("materials.protection.close") }
        }.padding(24).frame(width: 660).disabled(library.busy).interactiveDismissDisabled(library.busy)
    }
    private func request(_ action: Action) {
        if library.annotationDirty { pendingAction = action; confirmAnnotations = true } else { perform(action) }
    }
    private func perform(_ action: Action) {
        switch action {
        case .protections: library.reviewProtections(protections: model.materialDeletionProtections, files: model.materialDeletionFiles)
        case .batchDelete: library.reviewBatchDeletion(protections: model.materialDeletionProtections, files: model.materialDeletionFiles)
        case .delete: library.reviewDeletion(protections: model.materialDeletionProtections, files: model.materialDeletionFiles)
        case .scope(let value): _ = library.showTrash(value)
        case .trash: library.changeTrashState()
        case .select(let item): _ = library.select(item, discardEdits: true)
        case .close: library.cancel(); dismiss()
        case .open(let original):
            openOriginal = original; openClip = false
            if model.instrumentDirty { confirmOpen = true } else { open() }
        case .parent(let id): Task { await library.reveal(id) }
        case .reedit:
            openOriginal = false; openClip = true
            if model.instrumentDirty { confirmOpen = true } else { open() }
        }
    }
    private func open() {
        guard let selected = library.selected else { return }
        model.stop(); model.library.stopPreview()
        Task { if await model.openMaterial(selected.id, original: openOriginal, clip: openClip) { dismiss() } }
    }
}

private struct MaterialDeletionReview: View {
    let plan: MaterialDeletionPlan
    let busy: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(plan.alreadyDeleted ? "音声回収を再確認" : "素材を完全削除").font(.title2)
            Text("削除対象: \(plan.records.count) 件").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.records, id: \.id) { record in
                        Text(record.name).font(.headline)
                        Text(record.provenance.sourceName + " · " + record.location).font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: plan.records.count > 1 ? 140 : 65).accessibilityIdentifier("materials.delete.targets")
            Text("回収対象: \(plan.files.count) ファイル · " + ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file))
                .accessibilityIdentifier("materials.delete.capacity")
            Text("保護する音声: \(plan.protectedFiles) ファイル · 参照元 \(plan.references.count) 件")
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.references, id: \.self) { Text($0).font(.callout) }
                    if plan.references.isEmpty { Text("ほかの素材・登録済み楽器・編集中の参照はありません。") }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 160).accessibilityIdentifier("materials.delete.references")
            Text("素材の復元はできなくなり、タグ・メモを削除します。元曲名・位置・親子関係は来歴の参照記録として残します。保護中の音声と外部の楽器・構成ファイルは削除しません。")
                .font(.callout)
            Text("登録済み楽器・現在の構成と履歴を確認します。一覧外のファイルは走査しませんが、音声同梱の楽器・構成の演奏と内包来歴は保持されます。楽器の保護記録は自動解除しません。表示容量は共有音声の重複を除いた合計です。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("削除せず戻る", action: cancel).accessibilityIdentifier("materials.delete.cancel")
                Button(plan.alreadyDeleted ? "対象音声を回収する" : "完全削除する", role: .destructive, action: confirm)
                    .accessibilityIdentifier("materials.delete.confirm")
            }.disabled(busy)
            if busy { ProgressView("削除と音声回収を処理中…") }
        }.padding(24).frame(width: 620).fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(busy)
    }
}
