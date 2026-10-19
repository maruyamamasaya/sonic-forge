import Foundation
import Combine
import AVFoundation

@MainActor
final class MaterialLibraryModel: ObservableObject {
    let store: MaterialStore
    @Published private(set) var deletionSelection: Set<String> = []
    @Published private(set) var records: [MaterialItem] = []
    @Published private(set) var total = 0
    @Published private(set) var offset = 0
    @Published private(set) var pendingReclaims: [MaterialItem] = []
    @Published private(set) var availableTags: [MaterialTag] = []
    @Published private(set) var searching = false
    @Published var query = "" { didSet { if query != oldValue { refresh(debounce: true) } } }
    @Published var tagID: String? { didSet { if tagID != oldValue { refresh() } } }
    @Published private(set) var selected: MaterialItem?
    @Published private(set) var showingTrash = false
    @Published var tagsText = ""
    @Published var noteText = ""
    @Published private(set) var busy = false
    @Published private(set) var draft: MaterialDraft?
    @Published var protectionReview: MaterialStore.ProtectionReview?
    @Published var releasePlan: MaterialStore.ReleasePlan?
    @Published private(set) var protectedDeleted: [MaterialItem] = []
    @Published private(set) var deletionPlan: MaterialDeletionPlan?
    @Published private(set) var message = ""
    @Published private(set) var error: String?
    @Published private(set) var previewLoading = false
    @Published private(set) var previewKind: MaterialPreviewKind?
    @Published private(set) var previewPosition = 0.0
    @Published private(set) var previewDuration = 0.0
    private var task: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var navigationGeneration = UUID()
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var comparison: MaterialComparison?
    private var players: [MaterialPreviewKind: AVAudioPlayer] = [:]
    private var timer: AnyCancellable?
    private var activePlayer: AVAudioPlayer? { previewKind.flatMap { players[$0] } }
    var annotationDirty: Bool {
        guard let selected else { return false }
        return tagsText != selected.annotations.tags.joined(separator: ", ") || noteText != selected.annotations.note
    }
    var canPrevious: Bool { offset > 0 && !searching }
    var canNext: Bool { offset + records.count < total && !searching }
    init(store: MaterialStore) {
        self.store = store
        timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let player = self.activePlayer else { return }
            self.previewPosition = player.currentTime
            if !player.isPlaying { self.previewPosition = self.previewDuration; self.previewKind = nil }
        }
    }
    func refresh(resetPage: Bool = true, debounce: Bool = false) {
        deletionSelection = []
        stopPreview(); searchTask?.cancel(); searchGeneration = UUID()
        if resetPage { offset = 0 }
        let token = searchGeneration, query = self.query, tagID = self.tagID, offset = self.offset, trashed = showingTrash
        searching = true; error = nil
        searchTask = Task {
            defer { if searchGeneration == token { searching = false; searchTask = nil } }
            do {
                if debounce { try await Task.sleep(nanoseconds: 180_000_000) }
                let page = try await store.search(query: query, tagID: tagID, offset: offset, trashed: trashed)
                let tags = try await store.tags(trashed: trashed)
                let reclaims = try await store.pendingReclaims()
                let protected = try await store.protectedDeletedItems()
                try Task.checkCancellation()
                guard searchGeneration == token else { return }
                availableTags = tags; pendingReclaims = reclaims; protectedDeleted = protected
                if let tagID, !tags.contains(where: { $0.id == tagID }) { self.tagID = nil; return }
                // Clamp the last page after edits remove a search match.
                if offset > 0 && page.items.isEmpty && page.total > 0 {
                    self.offset = ((page.total - 1) / 50) * 50; refresh(resetPage: false); return
                }
                records = page.items; total = page.total
                if page.total == 0 { self.offset = 0 }
            } catch is CancellationError {} catch {
                guard searchGeneration == token else { return }
                records = []; total = 0; self.error = error.localizedDescription
            }
        }
    }
    func page(_ delta: Int) {
        guard delta == -1 ? canPrevious : canNext else { return }
        offset = max(0, offset + delta * 50); refresh(resetPage: false)
    }
    @discardableResult
    func select(_ item: MaterialItem, discardEdits: Bool = false) -> Bool {
        guard !busy, deletionPlan == nil, !annotationDirty || discardEdits else { return false }
        navigationGeneration = UUID()
        stopPreview(); selected = item; discardAnnotations(); error = nil
        return true
    }
    func reveal(_ id: String) async {
        guard !busy, !annotationDirty else { return }
        let navigation = navigationGeneration
        do {
            let item = try await store.item(id)
            try Task.checkCancellation()
            guard navigationGeneration == navigation, !busy, !annotationDirty else { return }
            if showingTrash != (item.trashedAt != nil) {
                showingTrash = item.trashedAt != nil; refresh()
            }
            _ = select(item)
        } catch is CancellationError {} catch { if navigationGeneration == navigation { self.error = error.localizedDescription } }
    }
    @discardableResult
    func showTrash(_ value: Bool) -> Bool {
        guard !busy, draft == nil, deletionPlan == nil, !annotationDirty else { return false }
        guard showingTrash != value else { return true }
        navigationGeneration = UUID()
        showingTrash = value; selected = nil; discardAnnotations(); message = ""; refresh()
        return true
    }
    func changeTrashState() {
        guard !busy, draft == nil, deletionPlan == nil, !annotationDirty, let selected, selected.deletedAt == nil else { return }
        navigationGeneration = UUID()
        let trash = selected.trashedAt == nil
        stopPreview(); busy = true; error = nil
        // Invalidate any older search result before mutation.
        searchTask?.cancel(); searchGeneration = UUID(); searching = false
        task = Task {
            defer { busy = false; task = nil }
            do {
                try await store.setTrashed(selected.id, trashed: trash)
                self.selected = nil; discardAnnotations()
                message = trash ? "ゴミ箱に移動しました。音声と来歴は保持しています。" : "素材を復元しました。"
                refresh(resetPage: false)
            } catch is CancellationError { message = "ゴミ箱の変更を取り消しました。" }
            catch { self.error = error.localizedDescription }
        }
    }
    func setDeletionSelected(_ id: String, selected: Bool) {
        guard showingTrash, !busy, !searching, deletionPlan == nil,
              records.contains(where: { $0.id == id && $0.trashedAt != nil }) else { return }
        if selected { deletionSelection.insert(id) } else { deletionSelection.remove(id) }
    }
    func selectPageForDeletion(_ selected: Bool) {
        guard showingTrash, !busy, !searching, deletionPlan == nil else { return }
        deletionSelection = selected ? Set(records.filter { $0.trashedAt != nil }.map(\.id)) : []
    }
    func reviewBatchDeletion(protections: [MaterialProtection], files: [URL]) {
        guard showingTrash, !busy, !searching, draft == nil, deletionPlan == nil,
              !annotationDirty, !deletionSelection.isEmpty else { return }
        let ids = deletionSelection
        stopPreview(); busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil }
            do {
                let plan = try await store.prepareBatchDeletion(ids, protections: protections, files: files)
                try Task.checkCancellation(); deletionPlan = plan
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func reviewDeletion(protections: [MaterialProtection], files: [URL]) {
        guard !busy, draft == nil, !annotationDirty, let selected, selected.trashedAt != nil || selected.deletedAt != nil else { return }
        stopPreview(); busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil }
            do {
                let plan = try await store.prepareDeletion(selected.id, protections: protections, files: files)
                try Task.checkCancellation()
                deletionPlan = plan
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func reviewProtections(protections: [MaterialProtection], files: [URL]) {
        guard !busy, draft == nil, !annotationDirty, let selected else { return }
        stopPreview(); busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil }
            do {
                let review = try await store.protectionReview(selected.id, protections: protections, files: files)
                try Task.checkCancellation(); protectionReview = review
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func reviewRelease(_ entry: MaterialStore.ProtectionEntry, protections: [MaterialProtection], files: [URL]) {
        guard !busy, let review = protectionReview else { return }
        busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil }
            do {
                let plan = try await store.prepareRelease(entry, materialID: review.materialID, protections: protections, files: files)
                try Task.checkCancellation(); releasePlan = plan
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func confirmRelease(protections: [MaterialProtection], files: [URL]) {
        guard !busy, let plan = releasePlan else { return }
        busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil }
            do {
                try await store.releaseProtection(plan, protections: protections, files: files)
                releasePlan = nil
                protectionReview = try await store.protectionReview(plan.materialID, protections: protections, files: files)
                message = "保護記録を解除しました。音声の回収は完全削除・未回収音声の確認から行ってください。"
                refresh(resetPage: false)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func dismissDeletion() { if !busy { deletionPlan = nil } }
    func confirmDeletion(protections: [MaterialProtection], files: [URL]) {
        guard !busy, let plan = deletionPlan else { return }
        stopPreview(); busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil; deletionPlan = nil }
            do {
                let result = try await store.deletePermanently(plan, protections: protections, files: files)
                self.selected = result.remainingFiles > 0 ? try await store.item(plan.record.id) : nil
                discardAnnotations()
                message = "完全削除済み \(plan.records.count)件 · 音声回収 " + ByteCountFormatter.string(fromByteCount: result.reclaimedBytes, countStyle: .file)
                if result.remainingFiles > 0 { message += " · 未回収\(result.remainingFiles)件。来歴から回収を再確認できます。" }
                refresh(resetPage: false)
            } catch is CancellationError { message = "完全削除を取り消しました。" }
            catch { self.error = error.localizedDescription }
        }
    }
    func discardAnnotations() {
        tagsText = selected?.annotations.tags.joined(separator: ", ") ?? ""
        noteText = selected?.annotations.note ?? ""
    }
    func saveAnnotations(onSaved: @escaping () -> Void = {}) {
        guard !busy, let selected, selected.deletedAt == nil else { return }
        let tags = tagsText.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",").components(separatedBy: ",")
        let note = noteText
        stopPreview(); busy = true; error = nil
        task = Task {
            var saved = false
            do {
                let annotations = try await store.updateAnnotations(selected.id, tags: tags, note: note)
                self.selected = MaterialItem(record: selected.record, annotations: annotations, trashedAt: selected.trashedAt)
                discardAnnotations(); message = "タグとメモを保存しました。"
                refresh(resetPage: false)
                saved = true
            } catch is CancellationError { message = "注釈の保存を取り消しました。" }
            catch { self.error = error.localizedDescription }
            // Finish this task before a continuation starts another mutation.
            busy = false; task = nil
            if saved { onSaved() }
        }
    }
    func prepare(origin: MaterialOrigin, selection: AudioSelection, name: String) {
        guard !busy, draft == nil else { return }
        stopPreview(); busy = true; error = nil; message = "元曲と選択範囲を保存用に準備中…"
        task = Task {
            defer { busy = false; task = nil }
            do {
                let next = try await store.prepare(origin: origin, selection: selection, name: name)
                if Task.isCancelled { await store.discard(next.id); throw CancellationError() }
                draft = next; message = "追加容量を確認して保存してください。"
            } catch is CancellationError { message = "保存準備を取り消しました。" }
            catch { self.error = error.localizedDescription; message = "保存していません。" }
        }
    }
    func commit() {
        guard !busy, let draft else { return }
        stopPreview(); busy = true; error = nil; message = "素材を保存中…"
        task = Task {
            defer { busy = false; task = nil; self.draft = nil }
            do {
                let saved = try await store.commit(draft.id)
                message = "保存済み · " + saved.name; refresh()
            } catch is CancellationError { message = "保存を取り消しました。" }
            catch { self.error = error.localizedDescription; message = "保存を完了できませんでした。" }
        }
    }
    func preview(_ kind: MaterialPreviewKind) {
        guard !busy, deletionPlan == nil, let selected else { return }
        if comparison?.record.id == selected.id {
            play(kind); return
        }
        stopPreview(); previewLoading = true; error = nil
        let token = previewGeneration
        previewTask = Task {
            defer { if previewGeneration == token { previewLoading = false; previewTask = nil } }
            do {
                let files = try await store.comparison(selected.id)
                try Task.checkCancellation()
                guard previewGeneration == token else { return }
                var candidates: [MaterialPreviewKind: AVAudioPlayer] = [:]
                for kind in MaterialPreviewKind.allCases {
                    let player = try AVAudioPlayer(contentsOf: files.url(kind))
                    player.volume = 0.2
                    guard player.prepareToPlay() else { throw AudioError.invalid("比較試聴を準備できませんでした。") }
                    candidates[kind] = player
                }
                comparison = files; players = candidates
                previewDuration = Double(files.record.selection.frameCount) / files.record.provenance.sampleRate
                play(kind)
            } catch is CancellationError {} catch {
                guard previewGeneration == token else { return }
                stopPreview(); self.error = error.localizedDescription
            }
        }
    }
    private func play(_ kind: MaterialPreviewKind) {
        let time = activePlayer?.currentTime ?? previewPosition
        let restart = previewKind == kind || time >= previewDuration
        activePlayer?.stop()
        guard let player = players[kind] else { return }
        player.currentTime = restart ? 0 : max(0, time)
        guard player.play() else { stopPreview(); error = "比較試聴を開始できませんでした。"; return }
        previewKind = kind; previewPosition = player.currentTime
    }
    func seekPreview(_ seconds: Double) {
        guard seconds.isFinite, comparison != nil else { return }
        previewPosition = max(0, min(previewDuration, seconds)); activePlayer?.currentTime = previewPosition
    }
    func stopPreview() {
        previewGeneration = UUID(); previewTask?.cancel(); previewTask = nil
        players.values.forEach { $0.stop() }; players = [:]; comparison = nil
        previewKind = nil; previewLoading = false; previewPosition = 0; previewDuration = 0
    }
    func cancel() {
        if !busy { deletionPlan = nil; protectionReview = nil; releasePlan = nil }
        navigationGeneration = UUID()
        stopPreview(); searchTask?.cancel(); searchTask = nil; searchGeneration = UUID(); searching = false
        task?.cancel()
        if !busy, let draft {
            self.draft = nil; message = "保存準備を破棄しました。"
            Task { await store.discard(draft.id) }
        }
    }
}
