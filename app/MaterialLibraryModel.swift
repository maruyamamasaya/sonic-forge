import Foundation
import Combine
import AVFoundation

@MainActor
final class MaterialLibraryModel: ObservableObject {
    let store: MaterialStore
    @Published private(set) var records: [MaterialItem] = []
    @Published private(set) var total = 0
    @Published private(set) var offset = 0
    @Published private(set) var availableTags: [MaterialTag] = []
    @Published private(set) var searching = false
    @Published var query = "" { didSet { if query != oldValue { refresh(debounce: true) } } }
    @Published var tagID: String? { didSet { if tagID != oldValue { refresh() } } }
    @Published private(set) var selected: MaterialItem?
    @Published var tagsText = ""
    @Published var noteText = ""
    @Published private(set) var busy = false
    @Published private(set) var draft: MaterialDraft?
    @Published private(set) var message = ""
    @Published private(set) var error: String?
    @Published private(set) var previewLoading = false
    @Published private(set) var previewKind: MaterialPreviewKind?
    @Published private(set) var previewPosition = 0.0
    @Published private(set) var previewDuration = 0.0
    private var task: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
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
        stopPreview(); searchTask?.cancel(); searchGeneration = UUID()
        if resetPage { offset = 0 }
        let token = searchGeneration, query = self.query, tagID = self.tagID, offset = self.offset
        searching = true; error = nil
        searchTask = Task {
            defer { if searchGeneration == token { searching = false; searchTask = nil } }
            do {
                if debounce { try await Task.sleep(nanoseconds: 180_000_000) }
                let page = try await store.search(query: query, tagID: tagID, offset: offset)
                let tags = try await store.tags()
                try Task.checkCancellation()
                guard searchGeneration == token else { return }
                availableTags = tags
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
        guard !busy, !annotationDirty || discardEdits else { return false }
        stopPreview(); selected = item; discardAnnotations(); error = nil
        return true
    }
    func discardAnnotations() {
        tagsText = selected?.annotations.tags.joined(separator: ", ") ?? ""
        noteText = selected?.annotations.note ?? ""
    }
    func saveAnnotations(onSaved: @escaping () -> Void = {}) {
        guard !busy, let selected else { return }
        let tags = tagsText.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",").components(separatedBy: ",")
        let note = noteText
        stopPreview(); busy = true; error = nil
        task = Task {
            defer { busy = false; task = nil }
            do {
                let annotations = try await store.updateAnnotations(selected.id, tags: tags, note: note)
                self.selected = MaterialItem(record: selected.record, annotations: annotations)
                discardAnnotations(); message = "タグとメモを保存しました。"
                refresh(resetPage: false)
                busy = false; onSaved()
            } catch is CancellationError { message = "注釈の保存を取り消しました。" }
            catch { self.error = error.localizedDescription }
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
        guard !busy, let selected else { return }
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
        stopPreview(); searchTask?.cancel(); searchTask = nil; searchGeneration = UUID(); searching = false
        task?.cancel()
        if !busy, let draft {
            self.draft = nil; message = "保存準備を破棄しました。"
            Task { await store.discard(draft.id) }
        }
    }
}
