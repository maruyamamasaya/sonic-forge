import AppKit
import AVFoundation
import Combine

struct EnsembleInstrument {
    let sample: InstrumentSample
    let root: Int
    let envelope: ADSRParameters
    let loop: SampleLoop
    let name: String
    var provenance: InstrumentProvenance? = nil
    static func load(_ url: URL) throws -> Self {
        let restored = try InstrumentDocument.load(url)
        defer { try? FileManager.default.removeItem(at: restored.directory) }
        return Self(sample: restored.sample, root: restored.rootNote, envelope: restored.envelope,
                    loop: restored.loop, name: url.deletingPathExtension().lastPathComponent, provenance: restored.provenance)
    }
}

@MainActor
final class EnsemblePart: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String { didSet { changed?() } }
    @Published fileprivate(set) var instrument: EnsembleInstrument? { didSet { changed?() } }
    @Published fileprivate(set) var instrumentURL: URL? { didSet { changed?() } }
    @Published fileprivate(set) var performance: PerformanceDocument { didSet { changed?() } }
    @Published var gainDB = 0.0 { didSet { changed?() } }
    @Published var compressor = PartCompressor.off { didSet { changed?() } }
    @Published var delay = PartDelay.off { didSet { changed?() } }
    @Published var reverb = 0.0 { didSet { changed?() } }
    @Published var eq = PartEQ.flat { didSet { changed?() } }
    @Published var pan = 0.0 { didSet { changed?() } }
    @Published var muted = false { didSet { changed?() } }
    @Published var startBeat = 0.0 { didSet { changed?() } }
    @Published var repeatCount = 1 { didSet { changed?() } }
    @Published var sectionID: UUID? { didSet { changed?() } }
    @Published fileprivate(set) var additionalClips: [EnsembleClip] = [] { didSet { changed?() } }
    fileprivate var changed: (() -> Void)?
    let primaryClipID = UUID()
    var allClips: [EnsembleClip] {
        [EnsembleClip(id: primaryClipID, performance: performance, startBeat: startBeat, repeatCount: repeatCount, sectionID: sectionID)] + additionalClips
    }
    @Published fileprivate(set) var voices = 0
    @Published fileprivate(set) var level: Float = -60
    init(name: String, instrument: EnsembleInstrument? = nil, performance: PerformanceDocument = .preset(.softChords)) {
        self.name = name; self.instrument = instrument; self.performance = performance
    }
}

/// Each part owns its MIDI channel/pedal state even when another part plays the same pitch.
@MainActor
final class EnsembleVoice {
    let sampler: SampleInstrument
    let instrument: EnsembleInstrument
    private let equalizer: AVAudioUnitEQ
    private let reverberator: AVAudioUnitReverb
    private let compressorUnit: AVAudioUnitEffect
    private var appliedCompressor = PartCompressor.off
    private let delayUnit: AVAudioUnitDelay
    private var appliedDelay = PartDelay.off
    private var appliedReverb = 0.0
    private var appliedEQ = PartEQ.flat
    private var pressed: Set<Int> = [], sustained: Set<Int> = [], pedals: Set<Int> = []
    private var parser = MIDIByteParser()
    init(instrument: EnsembleInstrument, engine: AVAudioEngine, mixer: AVAudioMixerNode) {
        self.instrument = instrument
        let input = AVAudioMixerNode()
        equalizer = PartEQ.makeNode()
        reverberator = PartReverb.makeNode()
        delayUnit = PartDelay.makeNode()
        compressorUnit = PartCompressor.makeNode()
        engine.attach(compressorUnit); engine.attach(input); engine.attach(equalizer); engine.attach(reverberator); engine.attach(delayUnit)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.connect(input, to: equalizer, format: format)
        engine.connect(equalizer, to: compressorUnit, format: format)
        engine.connect(compressorUnit, to: delayUnit, format: format)
        engine.connect(delayUnit, to: reverberator, format: format)
        engine.connect(reverberator, to: mixer, format: format)
        sampler = SampleInstrument(engine: engine, destination: input, panDestination: mixer)
        sampler.install(instrument.sample)
    }
    func setEQ(_ settings: PartEQ) {
        guard settings != appliedEQ else { return }
        settings.apply(to: equalizer); appliedEQ = settings
    }
    func setCompressor(_ settings: PartCompressor) {
        guard settings != appliedCompressor else { return }
        if settings.enabled != appliedCompressor.enabled { compressorUnit.auAudioUnit.reset() }
        settings.apply(to: compressorUnit); appliedCompressor = settings
    }
    func setDelay(_ settings: PartDelay) {
        guard settings != appliedDelay else { return }
        settings.apply(to: delayUnit)
        if settings.mix == 0 { delayUnit.auAudioUnit.reset() }
        appliedDelay = settings
    }
    func setReverb(_ amount: Double) {
        let safe = PartReverb.isValid(amount) ? amount : 0
        guard safe != appliedReverb else { return }
        reverberator.wetDryMix = Float(safe); reverberator.bypass = safe == 0
        if safe == 0 { reverberator.auAudioUnit.reset() }
        appliedReverb = safe
    }
    func receive(_ bytes: [UInt8]) throws {
        for message in parser.consume(bytes) {
            let key = Int(message.channel) * 128 + message.note
            switch message.kind {
            case let .on(velocity):
                let otherHeld = pressed.union(sustained).contains { $0 != key && $0 % 128 == message.note }
                sustained.remove(key); pressed.insert(key)
                if !otherHeld {
                    try sampler.play(note: message.note, root: instrument.root, envelope: instrument.envelope, loop: instrument.loop, velocity: velocity)
                }
            case .off:
                guard pressed.remove(key) != nil else { continue }
                if pedals.contains(Int(message.channel)) { sustained.insert(key) }
                releaseIfUnowned(message.note)
            case let .sustain(down):
                let channel = Int(message.channel)
                if down { pedals.insert(channel) }
                else {
                    pedals.remove(channel)
                    let notes = sustained.filter { $0 / 128 == channel }.map { $0 % 128 }
                    sustained = sustained.filter { $0 / 128 != channel }
                    notes.forEach { releaseIfUnowned($0) }
                }
            default: break
            }
        }
    }
    private func releaseIfUnowned(_ pitch: Int) {
        if !pressed.union(sustained).contains(where: { $0 % 128 == pitch }) { sampler.noteOff(pitch) }
    }
    var heldNotes: Set<Int> { Set(pressed.union(sustained).map { $0 % 128 }) }
    var pedalChannels: Set<Int> { pedals }
    func stop() { pressed.removeAll(); sustained.removeAll(); pedals.removeAll(); sampler.stop(); compressorUnit.auAudioUnit.reset(); delayUnit.auAudioUnit.reset(); reverberator.auAudioUnit.reset() }
}

@MainActor
final class EnsembleModel: ObservableObject {
    static let maximumParts = 4
    @Published var sections: [EnsembleSection] = [] { didSet { markDirty() } }
    @Published private(set) var parts: [EnsemblePart] = [] { didSet { oldValue.forEach { $0.changed = nil }; observeParts(); markDirty() } }
    @Published var tempo = 100.0 { didSet { if tempo != oldValue { markDirty() } } }
    @Published var limiter = MasterLimiter.off { didSet { if limiter != oldValue { markDirty() } } }
    @Published var masterDB = -12.0 { didSet { if masterDB != oldValue { markDirty() } } }
    @Published private(set) var playing = false
    @Published private(set) var releasing = false
    @Published private(set) var busy = false
    @Published private(set) var positionBeats = 0.0
    @Published private(set) var durationBeats = 0.0
    @Published private(set) var level: Float = -60
    @Published var error: String?
    @Published private(set) var exporting = false
    @Published private(set) var exportProgress = 0.0
    @Published private(set) var exportedURL: URL?
    private var exportTask: Task<Void, Never>?
    @Published private(set) var dirty = false
    @Published private(set) var fileURL: URL?
    @Published private(set) var fileMessage: String?
    private let defaults: UserDefaults
    private static let lastFileKey = "lastEnsemblePathV1"
    private struct NoteEdit { let before: PerformanceDocument; let after: PerformanceDocument }
    private struct NoteHistory { var undo: [NoteEdit] = []; var redo: [NoteEdit] = [] }
    @Published private var noteHistories: [String: NoteHistory] = [:]
    private var applyingNoteHistory = false
    private func noteKey(_ part: UUID, _ clip: UUID) -> String { part.uuidString + ":" + clip.uuidString }
    private var applyingSnapshot = false
    private var revision = UUID()
    private var attemptedRestore = false
    private var masterBus: EnsembleMasterBus?
    private var engine: AVAudioEngine?
    private var voices: [UUID: EnsembleVoice] = [:]
    private let meter = InstrumentMeter()
    private var task: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var generation = UUID()
    private var startedAt = 0.0
    private var playbackTempo = 100.0
    private var playbackStart = 0.0
    private var playbackEnd = 0.0
    @Published private(set) var playbackRange: Range<Double>?
    @Published private(set) var rangeLoopEnabled = false
    @Published private(set) var playbackPass = 0
    var arrangementLength: Double {
        max(EnsembleSections.end(sections), parts.flatMap(\.allClips).map {
            EnsembleSections.offset($0.sectionID, in: sections) + ($0.startBeat.isFinite ? max(0, $0.startBeat) : 0)
                + (EnsembleTimeline.repeatedLength($0.performance, count: $0.repeatCount) ?? 0)
        }.max() ?? 0)
    }
    @discardableResult func setPlaybackRange(start: Double, end: Double, enabled: Bool = true) -> Bool {
        guard canEdit else { return false }
        guard start.isFinite, end.isFinite, start >= 0, end - start >= 0.25, end <= arrangementLength else {
            error = "再生範囲は曲の中で、開始から終了まで¼拍以上を指定してください。"; return false
        }
        playbackRange = start..<end; rangeLoopEnabled = enabled; error = nil
        if enabled { positionBeats = start }
        return true
    }
    func loopSection(_ id: UUID) {
        guard let section = sections.first(where: { $0.id == id }) else { return }
        let start = EnsembleSections.offset(id, in: sections)
        _ = setPlaybackRange(start: start, end: start + section.beats)
    }
    func setRangeLoopEnabled(_ enabled: Bool) {
        guard canEdit else { return }
        if enabled {
            if let range = playbackRange { _ = setPlaybackRange(start: range.lowerBound, end: range.upperBound) }
            else { _ = setPlaybackRange(start: 0, end: arrangementLength) }
        } else { rangeLoopEnabled = false }
    }
    func seek(to beat: Double) {
        guard !busy, beat.isFinite, beat >= 0, beat <= arrangementLength else { return }
        let resume = playing
        if resume { stop(resetPosition: false) }
        positionBeats = rangeLoopEnabled && playbackRange != nil ? min(max(beat, playbackRange!.lowerBound), playbackRange!.upperBound) : beat
        if resume { play() }
    }
    func pause() {
        guard playing else { return }
        refresh(); stop(resetPosition: false)
    }
    private func reconcilePlaybackRange() {
        if let range = playbackRange, range.upperBound > arrangementLength {
            playbackRange = nil; rangeLoopEnabled = false
        }
        positionBeats = min(positionBeats, arrangementLength)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        historyState = songState()
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
    }
    var canEdit: Bool { !playing && !busy }
    private func markDirty() {
        guard !applyingSnapshot, historyDepth == 0 else { return }
        recordSongEdit()
    }
    private func observeParts() {
        let keys = Set(parts.flatMap { part in part.allClips.map { noteKey(part.id, $0.id) } })
        noteHistories = noteHistories.filter { keys.contains($0.key) }
        for part in parts { part.changed = { [weak self] in self?.markDirty() } }
    }
    // Value snapshots retain immutable PCM buffers, never engines or playback state.
    private struct SongPartState {
        let part: EnsemblePart
        let name: String
        let instrument: EnsembleInstrument?
        let instrumentURL: URL?
        let clips: [EnsembleClip]
        let gain: Double
        let pan: Double
        let eq: PartEQ
        let reverb: Double
        let compressor: PartCompressor
        let delay: PartDelay
        let muted: Bool
    }
    private struct SongState {
        let sections: [EnsembleSection]
        let parts: [SongPartState]
        let tempo: Double
        let master: Double
        let limiter: MasterLimiter
        func matches(_ other: Self) -> Bool {
            guard sections == other.sections, tempo == other.tempo, master == other.master, limiter == other.limiter,
                  parts.count == other.parts.count else { return false }
            return zip(parts, other.parts).allSatisfy { a, b in
                let sameInstrument: Bool
                switch (a.instrument, b.instrument) {
                case (nil, nil): sameInstrument = true
                case let (a?, b?):
                    sameInstrument = a.sample.buffer === b.sample.buffer && a.root == b.root &&
                        a.envelope == b.envelope && a.loop == b.loop && a.name == b.name && a.provenance == b.provenance
                default: sameInstrument = false
                }
                return a.part.id == b.part.id && a.name == b.name && sameInstrument &&
                    a.instrumentURL == b.instrumentURL && a.clips == b.clips && a.gain == b.gain && a.pan == b.pan && a.eq == b.eq && a.reverb == b.reverb && a.compressor == b.compressor && a.delay == b.delay && a.muted == b.muted
            }
        }
    }
    private struct SongEdit { let before: SongState; let after: SongState; let label: String }
    @Published private var songUndo: [SongEdit] = []
    @Published private var songRedo: [SongEdit] = []
    private var historyState: SongState?
    private var historyDepth = 0
    private var historyLabel = "曲の構成を編集"
    private func songState() -> SongState {
        SongState(sections: sections, parts: parts.map {
            SongPartState(part: $0, name: $0.name, instrument: $0.instrument, instrumentURL: $0.instrumentURL,
                          clips: $0.allClips, gain: $0.gainDB, pan: $0.pan, eq: $0.eq, reverb: $0.reverb, compressor: $0.compressor, delay: $0.delay, muted: $0.muted)
        }, tempo: tempo, master: masterDB, limiter: limiter)
    }
    var materialProtections: [MaterialProtection] {
        let states = [songState()] + songUndo.flatMap { [$0.before, $0.after] } + songRedo.flatMap { [$0.before, $0.after] }
        return states.flatMap(\.parts).compactMap { part in
            part.instrument?.provenance.map { MaterialProtection(record: $0.material, label: "構成・履歴: " + part.name) }
        }
    }
    private func beginSongEdit(_ label: String) {
        if historyDepth == 0 { historyLabel = label }
        historyDepth += 1
    }
    private func endSongEdit() {
        historyDepth -= 1
        if historyDepth == 0 { recordSongEdit(); historyLabel = "曲の構成を編集" }
    }
    private func recordSongEdit() {
        let after = songState()
        guard let before = historyState else { historyState = after; return }
        guard !before.matches(after) else { return }
        songUndo.append(SongEdit(before: before, after: after, label: historyLabel))
        if songUndo.count > 50 { songUndo.removeFirst() }
        songRedo.removeAll(); historyState = after
        revision = UUID(); dirty = true; fileMessage = nil
        reconcilePlaybackRange()
    }
    private func resetSongHistory() {
        songUndo.removeAll(); songRedo.removeAll(); historyState = songState()
    }
    var canUndoSong: Bool { canEdit && !songUndo.isEmpty && historyDepth == 0 }
    var canRedoSong: Bool { canEdit && !songRedo.isEmpty && historyDepth == 0 }
    var undoSongLabel: String { songUndo.last?.label ?? "曲の編集" }
    var redoSongLabel: String { songRedo.last?.label ?? "曲の編集" }
    @discardableResult func restoreSongEdit(redo: Bool = false) -> Bool {
        guard redo ? canRedoSong : canUndoSong, let edit = redo ? songRedo.last : songUndo.last else { return false }
        let state = redo ? edit.after : edit.before
        stop()
        applyingSnapshot = true
        // Detach removed parts as well, so retained references cannot create ghost edits.
        parts.forEach { $0.changed = nil }
        for value in state.parts {
            let part = value.part, first = value.clips[0]
            part.name = value.name; part.instrument = value.instrument; part.instrumentURL = value.instrumentURL
            part.performance = first.performance; part.startBeat = first.startBeat
            part.repeatCount = first.repeatCount; part.sectionID = first.sectionID
            part.additionalClips = Array(value.clips.dropFirst()); part.gainDB = value.gain; part.pan = value.pan; part.eq = value.eq; part.reverb = value.reverb; part.delay = value.delay; part.compressor = value.compressor; part.muted = value.muted
        }
        sections = state.sections; parts = state.parts.map(\.part); tempo = state.tempo; masterDB = state.master; limiter = state.limiter
        applyingSnapshot = false
        if redo { songRedo.removeLast(); songUndo.append(edit) }
        else { songUndo.removeLast(); songRedo.append(edit) }
        historyState = songState(); noteHistories.removeAll(); reconcilePlaybackRange()
        revision = UUID(); dirty = true; fileMessage = nil; error = nil
        durationBeats = 0; positionBeats = 0
        return true
    }
    var arrangementRevision: UUID { revision }
    func arrangementBrief(prompt: String) throws -> ArrangementBrief {
        guard canEdit else { throw AudioError.invalid("Stop All後、保存や書き出しの完了を待ってから編曲してください。") }
        let brief = ArrangementBrief(prompt: prompt, revision: revision, partIDs: parts.map(\.id), snapshot: try snapshot())
        try brief.validate(); return brief
    }
    @discardableResult func applyArrangement(_ proposal: ArrangementProposal, brief: ArrangementBrief) -> Bool {
        beginSongEdit("AI編曲を採用"); defer { endSongEdit() }
        guard canEdit else { error = "Stop All後、保存や書き出しの完了を待ってから採用してください。"; return false }
        do {
            guard revision == brief.revision, parts.map(\.id) == brief.partIDs else {
                throw AudioError.invalid("生成後に構成が変更されました。現在の構成から再生成してください。")
            }
            let result = try ArrangementGeneration.materialize(proposal, brief: brief)
            applyingSnapshot = true
            sections = result.sections; tempo = result.tempo
            for (part, value) in zip(parts, result.parts) {
                part.performance = value.performance; part.startBeat = value.startBeat
                part.repeatCount = value.repeatCount; part.sectionID = value.sectionID
                part.additionalClips = value.additionalClips; part.gainDB = value.gainDB; part.muted = value.muted
            }
            applyingSnapshot = false; noteHistories.removeAll(); durationBeats = 0; positionBeats = 0
            markDirty(); error = nil
            return true
        } catch { self.error = "編曲案を採用できませんでした。\n" + error.localizedDescription; return false }
    }
    func snapshot() throws -> EnsembleSnapshot {
        let values = try parts.map { part -> EnsemblePartSnapshot in
            guard let instrument = part.instrument else { throw AudioError.invalid("\(part.name): 楽器を割り当ててください。") }
            return EnsemblePartSnapshot(name: part.name, instrument: instrument, performance: part.performance, gainDB: part.gainDB, muted: part.muted, pan: part.pan, eq: part.eq, reverb: part.reverb, delay: part.delay, compressor: part.compressor, startBeat: part.startBeat, repeatCount: part.repeatCount, sectionID: part.sectionID, additionalClips: part.additionalClips)
        }
        let result = EnsembleSnapshot(tempo: tempo, masterDB: masterDB, parts: values, sections: sections, limiter: limiter)
        try EnsembleDocument.validate(result)
        return result
    }
    @discardableResult func save(to url: URL, remember: Bool = true) async -> Bool {
        guard canEdit else { return false }
        do {
            let saved = try snapshot(), savedRevision = revision
            busy = true; defer { busy = false }
            try await Task.detached(priority: .userInitiated) { try EnsembleDocument.save(saved, to: url) }.value
            fileURL = url
            if revision == savedRevision { dirty = false }
            if remember { defaults.set(url.path, forKey: Self.lastFileKey) }
            fileMessage = "Saved · " + url.lastPathComponent; error = nil
            return true
        } catch { self.error = "構成を保存できませんでした。\n" + error.localizedDescription; return false }
    }
    @discardableResult func load(_ url: URL, remember: Bool = true) async -> Bool {
        guard canEdit else { return false }
        busy = true; defer { busy = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try EnsembleDocument.load(url) }.value
            let replacements = loaded.parts.map { item -> EnsemblePart in
                let part = EnsemblePart(name: item.name, instrument: item.instrument, performance: item.performance)
                part.gainDB = item.gainDB; part.pan = item.pan; part.eq = item.eq; part.reverb = item.reverb; part.delay = item.delay; part.compressor = item.compressor; part.muted = item.muted; part.startBeat = item.startBeat; part.repeatCount = item.repeatCount; part.sectionID = item.sectionID; part.additionalClips = item.additionalClips
                return part
            }
            stop(); durationBeats = 0; playbackRange = nil; rangeLoopEnabled = false
            applyingSnapshot = true
            sections = loaded.sections; parts = replacements; tempo = loaded.tempo; masterDB = loaded.masterDB; limiter = loaded.limiter
            applyingSnapshot = false; noteHistories.removeAll(); resetSongHistory(); revision = UUID(); dirty = false; fileURL = url
            if remember { defaults.set(url.path, forKey: Self.lastFileKey) }
            fileMessage = "Opened · " + url.lastPathComponent; error = nil
            return true
        } catch { self.error = "構成を開けませんでした。\n" + error.localizedDescription; return false }
    }
    func restoreLastSession() async {
        guard !attemptedRestore else { return }
        attemptedRestore = true
        guard let path = defaults.string(forKey: Self.lastFileKey) else { return }
        if await load(URL(fileURLWithPath: path), remember: false) {
            fileMessage = "Restored · " + URL(fileURLWithPath: path).lastPathComponent
        } else {
            error = "前回の構成を復元できませんでした。Open…から別の構成を選択できます。\n" + (error ?? "")
        }
    }
    func savePanel() {
        guard canEdit else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.sonicForgeEnsemble]; panel.canCreateDirectories = true
        panel.title = "曲の構成を保存"
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "My Ensemble.sfensemble"
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.message = "全パートの音源・設定・演奏・音量・ミュートと共通テンポをまとめて保存します。"
        if panel.runModal() == .OK, let url = panel.url { Task { await save(to: url) } }
    }
    func openPanel() {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.sonicForgeEnsemble]; panel.canChooseDirectories = false
        panel.title = "曲の構成を開く"
        if panel.runModal() == .OK, let url = panel.url { Task { await load(url) } }
    }

    func exportPanel(protecting sources: [URL] = []) {
        guard canEdit else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.title = "曲全体をWAVに書き出す"
        panel.nameFieldStringValue = "Ensemble.wav"
        panel.message = "48 kHz・ステレオ・32-bit Float・開始位置・音量・消音・余韻を反映"
        if panel.runModal() == .OK, let url = panel.url {
            exportTask = Task { await exportWAV(to: url, protecting: sources) }
        }
    }
    func cancelExport() { exportTask?.cancel() }
    @discardableResult func exportWAV(to url: URL, protecting sources: [URL] = []) async -> Bool {
        guard canEdit else { return false }
        do {
            let saved = try snapshot()
            let protected = sources + parts.compactMap(\.instrumentURL) + (fileURL.map { [$0] } ?? [])
            busy = true; exporting = true; exportProgress = 0; exportedURL = nil
            defer { busy = false; exporting = false }
            try await EnsembleExport.write(saved, to: url, protecting: protected) { self.exportProgress = $0 }
            exportedURL = url; fileMessage = "Exported · " + url.lastPathComponent; error = nil
            return true
        } catch is CancellationError { fileMessage = "Export cancelled"; return false }
        catch { self.error = "WAVを書き出せませんでした。\n" + error.localizedDescription; return false }
    }

    @discardableResult func addPart(instrument: EnsembleInstrument? = nil, performance: PerformanceDocument = .preset(.softChords)) -> EnsemblePart? {
        guard canEdit, parts.count < Self.maximumParts else { return nil }
        let part = EnsemblePart(name: "Part \(parts.count + 1)", instrument: instrument, performance: performance)
        parts.append(part); error = nil; return part
    }
    func addSection() {
        guard canEdit, sections.count < 8 else { return }
        sections.append(EnsembleSection(name: "Section \(sections.count + 1)", beats: 16))
    }
    @discardableResult func duplicateSection(_ id: UUID) -> UUID? {
        beginSongEdit("セクションを複製"); defer { endSongEdit() }
        guard canEdit else { return nil }
        do {
            guard let index = sections.firstIndex(where: { $0.id == id }) else {
                throw AudioError.invalid("複製元のセクションが見つかりません。")
            }
            guard sections.count < 8 else { throw AudioError.invalid("セクションは最大8個です。") }
            var copy = sections[index]
            copy.id = UUID(); copy.name = String(copy.name.prefix(33)) + " · Copy"
            var candidateSections = sections
            candidateSections.insert(copy, at: index + 1)
            try EnsembleSections.validate(candidateSections)
            let additions = parts.map { part in
                part.allClips.filter { $0.sectionID == id }.map { source -> EnsembleClip in
                    var clip = source; clip.id = UUID(); clip.sectionID = copy.id; return clip
                }
            }
            // Insertion also shifts later sections: validate every part, including Song clips.
            for (part, clips) in zip(parts, additions) {
                guard let instrument = part.instrument else { throw AudioError.invalid("先に各パートへ楽器を割り当ててください。") }
                try EnsembleClips.validate(part.allClips + clips, root: instrument.root, sections: candidateSections)
            }
            applyingSnapshot = true
            sections = candidateSections
            for (part, clips) in zip(parts, additions) where !clips.isEmpty { part.additionalClips.append(contentsOf: clips) }
            applyingSnapshot = false; markDirty(); error = nil
            return copy.id
        } catch { self.error = "セクションを複製できませんでした。\n" + error.localizedDescription; return nil }
    }
    func reorderSection(_ id: UUID, by delta: Int) {
        guard canEdit, let index = sections.firstIndex(where: { $0.id == id }), sections.indices.contains(index + delta) else { return }
        sections.swapAt(index, index + delta)
    }
    func removeSection(_ id: UUID) {
        guard canEdit else { return }
        guard !parts.contains(where: { $0.allClips.contains(where: { $0.sectionID == id }) }) else { error = "割り当て済みのパートをSongへ変更してから削除してください。"; return }
        sections.removeAll { $0.id == id }; error = nil
    }
    func sectionOffset(for part: EnsemblePart) -> Double { EnsembleSections.offset(part.sectionID, in: sections) }
    func maximumStart(for part: EnsemblePart) -> Double {
        guard let section = sections.first(where: { $0.id == part.sectionID }) else { return 256 }
        return max(0, min(256, section.beats - (EnsembleTimeline.repeatedLength(part.performance, count: part.repeatCount) ?? 0)))
    }
    func addSongDemo() async {
        beginSongEdit("デモ曲を追加"); defer { endSongEdit() }
        guard canEdit else { return }
        guard parts.isEmpty && sections.isEmpty else { error = "Demo Songはパートとセクションが空のときに追加できます。既存構成は先に保存してください。"; return }
        await addDemos()
        guard parts.count == 2 else { return }
        sections = [EnsembleSection(name: "Intro", beats: 8), EnsembleSection(name: "Aメロ", beats: 16), EnsembleSection(name: "サビ", beats: 16)]
        let intro = parts[0], verse = parts[1]
        let chorus = EnsemblePart(name: "Chorus Pad", instrument: intro.instrument, performance: intro.performance)
        var short = intro.performance
        short.notes = Array(short.notes.prefix(3)); short.pedals = []
        intro.performance = short; intro.repeatCount = 2; intro.sectionID = sections[0].id; intro.name = "Intro Pad"
        verse.sectionID = sections[1].id; verse.name = "Verse Pluck"
        chorus.sectionID = sections[2].id; parts.append(chorus); error = nil
    }
    func addClip(part id: UUID, sectionID: UUID?) {
        guard canEdit, let part = parts.first(where: { $0.id == id }), part.additionalClips.count < 7 else { return }
        part.additionalClips.append(EnsembleClip(performance: part.performance, sectionID: sectionID))
    }
    @discardableResult func duplicateClip(part id: UUID, clip clipID: UUID, to sectionID: UUID?) -> UUID? {
        guard canEdit else { return nil }
        do {
            guard let part = parts.first(where: { $0.id == id }), let source = part.allClips.first(where: { $0.id == clipID }) else {
                throw AudioError.invalid("複製元のクリップが見つかりません。")
            }
            guard part.additionalClips.count < 7 else { throw AudioError.invalid("1パートのクリップは最大8個です。") }
            guard let instrument = part.instrument else { throw AudioError.invalid("先に楽器を割り当ててください。") }
            try EnsembleSections.validate(sections)
            var copy = source
            copy.id = UUID(); copy.sectionID = sectionID
            try EnsembleClips.validate(part.allClips + [copy], root: instrument.root, sections: sections)
            part.additionalClips.append(copy); error = nil
            return copy.id
        } catch { self.error = "クリップを複製できませんでした。\n" + error.localizedDescription; return nil }
    }
    func editClip(part id: UUID, clip clipID: UUID, change: (inout EnsembleClip) -> Void) {
        beginSongEdit("クリップを編集"); defer { endSongEdit() }
        guard canEdit, let part = parts.first(where: { $0.id == id }) else { return }
        let before = part.allClips.first { $0.id == clipID }?.performance
        if clipID == part.primaryClipID {
            var clip = part.allClips[0]; change(&clip)
            part.performance = clip.performance; part.startBeat = clip.startBeat
            part.repeatCount = clip.repeatCount; part.sectionID = clip.sectionID; markDirty()
        } else if let index = part.additionalClips.firstIndex(where: { $0.id == clipID }) {
            change(&part.additionalClips[index])
        }
        if !applyingNoteHistory, before != part.allClips.first(where: { $0.id == clipID })?.performance {
            noteHistories.removeValue(forKey: noteKey(id, clipID))
        }
    }
    func setInstrumentSettings(part id: UUID, root: Int, envelope: ADSRParameters, loop: SampleLoop) {
        beginSongEdit("楽器設定を変更"); defer { endSongEdit() }
        guard canEdit, let part = parts.first(where: { $0.id == id }), let old = part.instrument else { return }
        guard (48...72).contains(root), envelope.isValid,
              loop.isValid(frameCount: Int64(old.sample.buffer.frameLength), sampleRate: old.sample.buffer.format.sampleRate) else {
            error = "楽器の基準音・ADSR・ループ範囲を確認してください。"; return
        }
        part.instrument = EnsembleInstrument(sample: old.sample, root: root, envelope: envelope, loop: loop, name: old.name, provenance: old.provenance)
        markDirty(); error = nil
    }
    func removeClip(part id: UUID, clip clipID: UUID) {
        guard canEdit, let part = parts.first(where: { $0.id == id }) else { return }
        part.additionalClips.removeAll { $0.id == clipID }
        noteHistories.removeValue(forKey: noteKey(id, clipID))
    }
    func setClipPerformance(_ performance: PerformanceDocument, part id: UUID, clip clipID: UUID) {
        guard canEdit, let part = parts.first(where: { $0.id == id }) else { return }
        do { _ = try performance.events(root: part.instrument?.root); editClip(part: id, clip: clipID) { $0.performance = performance }; error = nil }
        catch { self.error = error.localizedDescription }
    }
    /// Session-local musical clipboard: relative beats, sounding MIDI pitch/velocity.
    @Published private(set) var copiedNotes: [PerformanceNote] = []
    @discardableResult
    func copyClipNotes(part id: UUID, clip clipID: UUID, indices: Set<Int>) -> Bool {
        guard canEdit, let part = parts.first(where: { $0.id == id }),
              let clip = part.allClips.first(where: { $0.id == clipID }),
              !indices.isEmpty, indices.allSatisfy({ clip.performance.notes.indices.contains($0) }) else { return false }
        do {
            _ = try clip.performance.events(root: part.instrument?.root)
            let origin = indices.map { clip.performance.notes[$0].beat }.min()!
            copiedNotes = indices.sorted().map { index in
                var note = clip.performance.notes[index]
                note.beat -= origin; note.pitch += clip.performance.transpose
                note.velocity = min(127, max(1, Int((Double(note.velocity) * clip.performance.velocityPercent / 100).rounded())))
                return note
            }
            error = nil; return true
        } catch { self.error = "音符をコピーできませんでした。\n" + error.localizedDescription; return false }
    }
    func pasteClipNotes(part id: UUID, clip clipID: UUID, at beat: Double) -> Set<Int>? {
        guard canEdit, let part = parts.first(where: { $0.id == id }),
              let clip = part.allClips.first(where: { $0.id == clipID }), !copiedNotes.isEmpty else { return nil }
        guard beat.isFinite, (0...256).contains(beat) else {
            error = "貼り付け位置は0〜256拍で指定してください。"; return nil
        }
        do { _ = try clip.performance.events(root: part.instrument?.root) }
        catch { self.error = "貼り付け先の演奏データを確認してください。\n" + error.localizedDescription; return nil }
        var pasted: [PerformanceNote] = []
        for source in copiedNotes {
            guard let velocity = (1...127).first(where: {
                min(127, max(1, Int((Double($0) * clip.performance.velocityPercent / 100).rounded()))) == source.velocity
            }) else {
                error = "貼り付け先のVelocity %では元の強弱を再現できません。クリップのVelocityを100%にしてから貼り付けてください。"; return nil
            }
            var note = source
            note.beat += beat; note.pitch -= clip.performance.transpose; note.velocity = velocity
            pasted.append(note)
        }
        let start = clip.performance.notes.count
        return editClipNotes(part: id, clip: clipID, change: { $0.append(contentsOf: pasted) })
            ? Set(start..<(start + pasted.count)) : nil
    }

    enum NoteGroupAction { case move(Double, Int), duplicate(Double, Int), delete, quantize(NoteQuantizeGrid), velocity(Int), velocityOffset(Int), duration(Double), durationScale(Double) }
    /// Apply a selection as one validated edit and one undo step.
    func editNoteGroup(part id: UUID, clip clipID: UUID, indices: Set<Int>, action: NoteGroupAction) -> Set<Int>? {
        guard canEdit, let clip = parts.first(where: { $0.id == id })?.allClips.first(where: { $0.id == clipID }),
              !indices.isEmpty, indices.allSatisfy({ clip.performance.notes.indices.contains($0) }) else { return nil }
        var result = indices
        let success = editClipNotes(part: id, clip: clipID) { notes in
            switch action {
            case let .duration(value):
                guard value.isFinite, value > 0, value <= 256 else { notes[0].duration = .nan; return }
                for index in indices { notes[index].duration = value }
            case let .durationScale(factor):
                guard factor.isFinite, factor > 0 else { notes[0].duration = .nan; return }
                for index in indices { notes[index].duration *= factor }
            case let .velocity(value):
                guard (1...127).contains(value) else { notes[0].velocity = 0; return }
                for index in indices { notes[index].velocity = value }
            case let .velocityOffset(offset):
                guard (-126...126).contains(offset) else { notes[0].velocity = 0; return }
                for index in indices { notes[index].velocity = min(127, max(1, notes[index].velocity + offset)) }
            case let .quantize(grid):
                for index in indices { notes[index].beat = grid.snap(notes[index].beat) }
            case .delete:
                notes = notes.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
                result = []
            case let .move(beats, semitones), let .duplicate(beats, semitones):
                guard beats.isFinite, (-256...256).contains(beats), (-127...127).contains(semitones) else {
                    notes[0].beat = .nan; return
                }
                let copies = indices.sorted().map { index -> PerformanceNote in
                    var note = notes[index]; note.beat += beats; note.pitch += semitones; return note
                }
                if case .duplicate = action {
                    result = Set(notes.count..<(notes.count + copies.count)); notes.append(contentsOf: copies)
                } else {
                    for (index, note) in zip(indices.sorted(), copies) { notes[index] = note }
                }
            }
        }
        return success ? result : nil
    }

    /// Atomic note edits validate the complete part, including repeated placement and siblings.
    @discardableResult
    func editClipNotes(part id: UUID, clip clipID: UUID, change: (inout [PerformanceNote]) -> Void) -> Bool {
        beginSongEdit("音符を編集"); defer { endSongEdit() }
        guard canEdit, let part = parts.first(where: { $0.id == id }),
              let index = part.allClips.firstIndex(where: { $0.id == clipID }) else { return false }
        var clips = part.allClips
        change(&clips[index].performance.notes)
        do {
            try EnsembleSections.validate(sections)
            try EnsembleClips.validate(clips, root: part.instrument?.root ?? 60, sections: sections)
            if clips[index] != part.allClips[index] {
                let before = part.allClips[index].performance, after = clips[index].performance
                let key = noteKey(id, clipID)
                var history = noteHistories[key] ?? NoteHistory()
                // A preset or externally replaced document must never inherit stale edits.
                if let last = history.undo.last, last.after != before { history = NoteHistory() }
                applyingNoteHistory = true
                editClip(part: id, clip: clipID) { $0.performance = after }
                applyingNoteHistory = false
                history.undo.append(NoteEdit(before: before, after: after))
                if history.undo.count > 50 { history.undo.removeFirst() }
                history.redo.removeAll(); noteHistories[key] = history
            }
            error = nil; return true
        } catch { self.error = "音符を変更できませんでした。\n" + error.localizedDescription; return false }
    }

    func canUndoNotes(part id: UUID, clip clipID: UUID) -> Bool {
        guard canEdit, let edit = noteHistories[noteKey(id, clipID)]?.undo.last else { return false }
        return parts.first { $0.id == id }?.allClips.first { $0.id == clipID }?.performance == edit.after
    }
    func canRedoNotes(part id: UUID, clip clipID: UUID) -> Bool {
        guard canEdit, let edit = noteHistories[noteKey(id, clipID)]?.redo.last else { return false }
        return parts.first { $0.id == id }?.allClips.first { $0.id == clipID }?.performance == edit.before
    }
    @discardableResult
    func restoreNoteEdit(part id: UUID, clip clipID: UUID, redo: Bool = false) -> Bool {
        beginSongEdit("音符の履歴を適用"); defer { endSongEdit() }
        guard redo ? canRedoNotes(part: id, clip: clipID) : canUndoNotes(part: id, clip: clipID),
              let part = parts.first(where: { $0.id == id }),
              let index = part.allClips.firstIndex(where: { $0.id == clipID }) else { return false }
        let key = noteKey(id, clipID)
        var history = noteHistories[key]!
        let edit = redo ? history.redo.last! : history.undo.last!
        var clips = part.allClips
        clips[index].performance = redo ? edit.after : edit.before
        do {
            try EnsembleSections.validate(sections)
            try EnsembleClips.validate(clips, root: part.instrument?.root ?? 60, sections: sections)
            applyingNoteHistory = true
            editClip(part: id, clip: clipID) { $0.performance = clips[index].performance }
            applyingNoteHistory = false
            if redo { history.redo.removeLast(); history.undo.append(edit) }
            else { history.undo.removeLast(); history.redo.append(edit) }
            noteHistories[key] = history; error = nil; return true
        } catch { self.error = "音符の履歴を適用できませんでした。\n" + error.localizedDescription; return false }
    }

    func openClipPerformance(part id: UUID, clip clipID: UUID) {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.sonicForgePerformance, .json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { setClipPerformance(try PerformanceDocument.load(url), part: id, clip: clipID) }
        catch { self.error = "演奏を開けませんでした。\n" + error.localizedDescription }
    }
    func movePart(_ id: UUID, to beat: Double, clip clipID: UUID? = nil) {
        guard canEdit, beat.isFinite, (0...256).contains(beat), let part = parts.first(where: { $0.id == id }) else { return }
        if let clipID, clipID != part.primaryClipID {
            guard let clip = part.additionalClips.first(where: { $0.id == clipID }) else { return }
            let maximum = sections.first(where: { $0.id == clip.sectionID }).map {
                max(0, min(256, $0.beats - (EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount) ?? 0)))
            } ?? 256
            editClip(part: id, clip: clipID) { $0.startBeat = min(beat, maximum) }
        } else { part.startBeat = min(beat, maximumStart(for: part)) }
    }
    func addSharedSongDemo() async {
        beginSongEdit("デモ曲を追加"); defer { endSongEdit() }
        await addSongDemo()
        guard error == nil, parts.count == 3, sections.count == 3 else { return }
        let pad = parts[0], chorus = parts[2], pluck = parts[1]
        pad.name = "Shared Pad"
        pad.additionalClips = [EnsembleClip(performance: chorus.performance, sectionID: sections[2].id)]
        pluck.additionalClips = [EnsembleClip(performance: .preset(.arpeggio), sectionID: sections[2].id)]
        parts.removeLast()
    }
    func remove(_ id: UUID) { guard canEdit else { return }; parts.removeAll { $0.id == id } }
    func setPerformance(_ document: PerformanceDocument, part id: UUID) {
        guard canEdit, let part = parts.first(where: { $0.id == id }) else { return }
        do { _ = try document.events(root: part.instrument?.root); editClip(part: id, clip: part.primaryClipID) { $0.performance = document }; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func loadInstrument(_ url: URL, part id: UUID) async {
        beginSongEdit("楽器を読み込み"); defer { endSongEdit() }
        guard canEdit, let part = parts.first(where: { $0.id == id }) else { return }
        busy = true; defer { busy = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try EnsembleInstrument.load(url) }.value
            // File failure must not replace the prior part. Range is checked at Play All.
            part.instrument = loaded; part.instrumentURL = url; markDirty(); error = nil
        } catch { self.error = "パートの楽器を読み込めませんでした。\n" + error.localizedDescription }
    }
    func openInstrument(_ id: UUID) {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.sonicForgeInstrument]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { Task { await loadInstrument(url, part: id) } }
    }
    func openPerformance(_ id: UUID) {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.sonicForgePerformance, .json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { setPerformance(try PerformanceDocument.load(url), part: id) }
        catch { self.error = "パートの演奏を読み込めませんでした。\n" + error.localizedDescription }
    }
    func addDemos(staggered: Bool = false, repeating: Bool = false, panned: Bool = false, equalized: Bool = false, reverberant: Bool = false, delayed: Bool = false, compressed: Bool = false, limited: Bool = false) async {
        beginSongEdit("デモを追加"); defer { endSongEdit() }
        guard canEdit else { return }
        guard parts.count <= Self.maximumParts - 2 else { error = "デモ2パートを追加するには空きを2つ用意してください。"; return }
        busy = true; defer { busy = false }
        do {
            let sample = try await Task.detached(priority: .userInitiated) {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-EnsembleDemo-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("demo.wav")
                try DemoAudio.write(to: url)
                return try InstrumentSample.load(url: url, selection: AudioSelection(startFrame: 0, endFrame: 96000))
            }.value
            let soft = EnsembleInstrument(sample: sample, root: 57,
                envelope: ADSRParameters(attack: 0.2, decay: 0.3, sustain: 0.7, release: 0.5),
                loop: SampleLoop(enabled: true, endFrame: 96000, crossfadeFrames: 2400), name: "Demo — Soft pad")
            let pluck = EnsembleInstrument(sample: sample, root: 57,
                envelope: ADSRParameters(attack: 0.003, decay: 0.12, sustain: 0.3, release: 0.12),
                loop: SampleLoop(endFrame: 96000), name: "Demo — Metal pluck")
            let chord = EnsemblePart(name: "Soft Chords", instrument: soft, performance: try PerformanceGeneration.demo(PerformanceBrief(prompt: "落ち着いた和音", root: 57)))
            let phrase = EnsemblePart(name: "Bouncy Phrase", instrument: pluck, performance: try PerformanceGeneration.demo(PerformanceBrief(prompt: "跳ねたフレーズ", root: 57)))
            if panned { chord.pan = -0.65; phrase.pan = 0.65 }
            if equalized { chord.eq = PartEQ(lowDB: 6, midDB: -3, highDB: -6); phrase.eq = PartEQ(lowDB: -6, midDB: 3, highDB: 6) }
            if reverberant { chord.reverb = 35; phrase.reverb = 15 }
            if delayed { chord.delay = PartDelay(timeMS: 350, mix: 18, feedback: 25); phrase.delay = PartDelay(timeMS: 250, mix: 30, feedback: 40) }
            if compressed {
                chord.compressor = PartCompressor(enabled: true, thresholdDB: -30, headroomDB: 5)
                phrase.compressor = PartCompressor(enabled: true, thresholdDB: -30, headroomDB: 3, attackMS: 2, releaseMS: 100)
                var performance = phrase.performance
                for index in performance.notes.indices { performance.notes[index].velocity = index.isMultiple(of: 2) ? 45 : 120 }
                phrase.performance = performance
            }
            if limited {
                limiter = .standard; masterDB = 0
                for part in [chord, phrase] {
                    part.eq = PartEQ(lowDB: 12, midDB: 12, highDB: 12)
                    part.compressor = PartCompressor(enabled: true, thresholdDB: 0, headroomDB: 40, makeupDB: 24)
                    var performance = part.performance
                    for index in performance.notes.indices { performance.notes[index].velocity = 127 }
                    part.performance = performance
                    if let instrument = part.instrument {
                        part.instrument = EnsembleInstrument(sample: instrument.sample, root: instrument.root,
                            envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.5),
                            loop: instrument.loop, name: instrument.name, provenance: instrument.provenance)
                    }
                }
            }
            phrase.startBeat = staggered ? 4 : 0
            if repeating { chord.repeatCount = 2; phrase.repeatCount = 3 }
            parts.append(contentsOf: [chord, phrase]); error = nil
        } catch { self.error = "デモパートを追加できませんでした。\n" + error.localizedDescription }
    }
    struct Event {
        let time: Double
        let part: UUID
        let bytes: [UInt8]
    }
    /// Shared tempo overrides each performance's stored tempo without editing its document.
    func timeline() throws -> [Event] {
        guard !parts.isEmpty, parts.count <= Self.maximumParts, tempo.isFinite, (40...240).contains(tempo),
              masterDB.isFinite, (-60...0).contains(masterDB), limiter.isValid else { throw AudioError.invalid("パート・テンポ・音量を確認してください。") }
        try EnsembleSections.validate(sections)
        var events: [Event] = []
        for part in parts {
            guard let instrument = part.instrument else { throw AudioError.invalid("\(part.name): 楽器を割り当ててください。") }
            guard part.startBeat.isFinite, (0...256).contains(part.startBeat), part.gainDB.isFinite, (-36...0).contains(part.gainDB), part.pan.isFinite, (-1...1).contains(part.pan), part.eq.isValid, PartReverb.isValid(part.reverb), part.delay.isValid, part.compressor.isValid, instrument.envelope.isValid,
                  instrument.loop.isValid(frameCount: Int64(instrument.sample.buffer.frameLength), sampleRate: instrument.sample.buffer.format.sampleRate) else {
                throw AudioError.invalid("\(part.name): 楽器設定・音量が無効です。")
            }
            do {
                events += try EnsembleClips.events(part.allClips, root: instrument.root, tempo: tempo, sections: sections).map { Event(time: $0.time, part: part.id, bytes: $0.bytes) } }
            catch { throw AudioError.invalid(part.name + ": " + error.localizedDescription) }
        }
        return events.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }.map(\.element)
    }
    func play() {
        guard canEdit else { return }
        do {
            let events = try timeline() // Validate every part before starting any audio.
            reconcilePlaybackRange()
            let total = arrangementLength
            let range = rangeLoopEnabled ? playbackRange : nil
            let begin = range.map { $0.contains(positionBeats) ? positionBeats : $0.lowerBound }
                ?? (positionBeats < total ? positionBeats : 0)
            let end = range?.upperBound ?? total
            let firstPlan = try EnsemblePlayback.plan(events: events, start: begin, end: end, tempo: tempo)
            // Full-song playback includes terminal note-offs/pedal-up at the song end.
            let terminal = range == nil ? events.filter { abs($0.time - total * 60 / tempo) < 1e-9 } : []
            stop(resetPosition: false)
            let engine = AVAudioEngine(); self.engine = engine
            let master = EnsembleMasterBus(engine: engine); masterBus = master
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [meter] buffer, _ in meter.update(buffer) }
            for (index, part) in parts.enumerated() {
                let mixer = AVAudioMixerNode(); engine.attach(mixer)
                engine.connect(mixer, to: master.input, fromBus: 0, toBus: AVAudioNodeBus(index), format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!)
                voices[part.id] = EnsembleVoice(instrument: part.instrument!, engine: engine, mixer: mixer)
            }
            updateGains()
            engine.prepare(); try engine.start()
            updateGains() // Apply pan after graph initialization, before the first note.
            durationBeats = total; playbackStart = begin; playbackEnd = end; positionBeats = begin
            playbackTempo = tempo; startedAt = ProcessInfo.processInfo.systemUptime
            playing = true; releasing = false; playbackPass = 1; error = nil
            let token = generation, fixedTempo = playbackTempo
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    var plan = firstPlan
                    while true {
                        for event in plan.initial { try self.voices[event.part]?.receive(event.bytes) }
                        for event in plan.events {
                            let delay = max(0, self.startedAt + event.time - ProcessInfo.processInfo.systemUptime)
                            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                            guard !Task.isCancelled, self.generation == token else { return }
                            try self.voices[event.part]?.receive(event.bytes)
                        }
                        let deadline = self.startedAt + (plan.end - plan.start) * 60 / fixedTempo
                        let remaining = deadline - ProcessInfo.processInfo.systemUptime
                        if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                        guard self.generation == token, !Task.isCancelled else { return }
                        if let range {
                            self.voices.values.forEach { $0.stop() }; self.masterBus?.reset()
                            plan = try EnsemblePlayback.plan(events: events, start: range.lowerBound, end: range.upperBound, tempo: fixedTempo)
                            self.startedAt = max(deadline, ProcessInfo.processInfo.systemUptime)
                            self.playbackStart = range.lowerBound; self.positionBeats = range.lowerBound
                            self.playbackPass += 1
                        } else { break }
                    }
                    for event in terminal { try self.voices[event.part]?.receive(event.bytes) }
                    self.positionBeats = end; self.releasing = true
                    let tailDeadline = ProcessInfo.processInfo.systemUptime + 6
                    while self.voices.values.contains(where: { $0.sampler.isSounding }) && ProcessInfo.processInfo.systemUptime < tailDeadline {
                        try await Task.sleep(nanoseconds: 33_000_000)
                        guard self.generation == token, !Task.isCancelled else { return }
                    }
                    let effectTail = self.parts.filter { !$0.muted }.map { PartReverb.tailSeconds($0.reverb) + $0.delay.tailSeconds }.max() ?? 0
                    if effectTail > 0 {
                        try await Task.sleep(nanoseconds: UInt64(effectTail * 1_000_000_000))
                        guard self.generation == token, !Task.isCancelled else { return }
                    }
                    self.stop(resetPosition: false)
                } catch is CancellationError { return }
                catch {
                    guard self.generation == token else { return }
                    self.stop(); self.error = "演奏を停止しました。\n" + error.localizedDescription
                }
            }
        } catch { stop(); self.error = "同時再生を開始できませんでした。\n" + error.localizedDescription }
    }
    private func updateGains() {
        // Four-part headroom; each sampler already reserves headroom for its eight voices.
        masterBus?.apply(limiter, masterDB: masterDB)
        for part in parts {
            voices[part.id]?.sampler.gain = part.muted ? 0 : Float(pow(10, max(-36, min(0, part.gainDB)) / 20))
            voices[part.id]?.sampler.pan = Float(part.pan.isFinite ? max(-1, min(1, part.pan)) : 0)
            voices[part.id]?.setEQ(part.eq)
            voices[part.id]?.setReverb(part.reverb)
            voices[part.id]?.setDelay(part.delay)
            voices[part.id]?.setCompressor(part.compressor)
        }
    }
    private func refresh() {
        guard playing else { return }
        updateGains()
        positionBeats = min(playbackEnd, max(playbackStart, playbackStart + (ProcessInfo.processInfo.systemUptime - startedAt) * playbackTempo / 60))
        level = meter.read().max() ?? -60
        for part in parts {
            guard let voice = voices[part.id] else { continue }
            voice.sampler.refreshCompletion(); part.voices = voice.sampler.soundingCount
            part.level = voice.sampler.meter.read().max() ?? -60
        }
    }
    func stop(resetPosition: Bool = true) {
        generation = UUID(); task?.cancel(); task = nil
        voices.values.forEach { $0.stop() }; masterBus?.reset(); engine?.stop(); masterBus = nil; voices.removeAll(); engine = nil
        playing = false; releasing = false; level = -60
        if resetPosition { positionBeats = 0 }
        for part in parts { part.voices = 0; part.level = -60 }
    }
    func heldNotes(part id: UUID) -> Set<Int> { voices[id]?.heldNotes ?? [] }
    func pedalChannels(part id: UUID) -> Set<Int> { voices[id]?.pedalChannels ?? [] }
}
