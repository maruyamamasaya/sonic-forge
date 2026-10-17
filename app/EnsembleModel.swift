import AppKit
import AVFoundation
import Combine

struct EnsembleInstrument {
    let sample: InstrumentSample
    let root: Int
    let envelope: ADSRParameters
    let loop: SampleLoop
    let name: String
    static func load(_ url: URL) throws -> Self {
        let restored = try InstrumentDocument.load(url)
        defer { try? FileManager.default.removeItem(at: restored.directory) }
        return Self(sample: restored.sample, root: restored.rootNote, envelope: restored.envelope,
                    loop: restored.loop, name: url.deletingPathExtension().lastPathComponent)
    }
}

@MainActor
final class EnsemblePart: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published fileprivate(set) var instrument: EnsembleInstrument?
    @Published fileprivate(set) var instrumentURL: URL?
    @Published fileprivate(set) var performance: PerformanceDocument
    @Published var gainDB = 0.0
    @Published var muted = false
    @Published var startBeat = 0.0
    @Published var repeatCount = 1
    @Published var sectionID: UUID?
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
    private var pressed: Set<Int> = [], sustained: Set<Int> = [], pedals: Set<Int> = []
    private var parser = MIDIByteParser()
    init(instrument: EnsembleInstrument, engine: AVAudioEngine, mixer: AVAudioMixerNode) {
        self.instrument = instrument
        sampler = SampleInstrument(engine: engine, destination: mixer)
        sampler.install(instrument.sample)
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
    func stop() { pressed.removeAll(); sustained.removeAll(); pedals.removeAll(); sampler.stop() }
}

@MainActor
final class EnsembleModel: ObservableObject {
    static let maximumParts = 4
    @Published var sections: [EnsembleSection] = [] { didSet { markDirty() } }
    @Published private(set) var parts: [EnsemblePart] = [] { didSet { observeParts(); markDirty() } }
    @Published var tempo = 100.0 { didSet { if tempo != oldValue { markDirty() } } }
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
    private var applyingSnapshot = false
    private var revision = UUID()
    private var partChanges: Set<AnyCancellable> = []
    private var attemptedRestore = false
    private var engine: AVAudioEngine?
    private var voices: [UUID: EnsembleVoice] = [:]
    private let meter = InstrumentMeter()
    private var task: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var generation = UUID()
    private var startedAt = 0.0
    private var playbackTempo = 100.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refresh() }
    }
    var canEdit: Bool { !playing && !busy }
    private func markDirty() {
        guard !applyingSnapshot else { return }
        revision = UUID(); dirty = true; fileMessage = nil
    }
    private func observeParts() {
        partChanges.removeAll()
        for part in parts {
            Publishers.Merge3(part.$name.dropFirst().removeDuplicates().map { _ in () },
                              part.$gainDB.dropFirst().removeDuplicates().map { _ in () },
                              part.$muted.dropFirst().removeDuplicates().map { _ in () })
                .sink { [weak self] in self?.markDirty() }.store(in: &partChanges)
            part.$sectionID.dropFirst().removeDuplicates().sink { [weak self] _ in self?.markDirty() }.store(in: &partChanges)
            part.$repeatCount.dropFirst().removeDuplicates().sink { [weak self] _ in self?.markDirty() }.store(in: &partChanges)
            part.$startBeat.dropFirst().removeDuplicates().sink { [weak self] _ in self?.markDirty() }.store(in: &partChanges)
        }
    }
    func snapshot() throws -> EnsembleSnapshot {
        let values = try parts.map { part -> EnsemblePartSnapshot in
            guard let instrument = part.instrument else { throw AudioError.invalid("\(part.name): 楽器を割り当ててください。") }
            return EnsemblePartSnapshot(name: part.name, instrument: instrument, performance: part.performance, gainDB: part.gainDB, muted: part.muted, startBeat: part.startBeat, repeatCount: part.repeatCount, sectionID: part.sectionID)
        }
        let result = EnsembleSnapshot(tempo: tempo, masterDB: masterDB, parts: values, sections: sections)
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
                part.gainDB = item.gainDB; part.muted = item.muted; part.startBeat = item.startBeat; part.repeatCount = item.repeatCount; part.sectionID = item.sectionID
                return part
            }
            stop(); durationBeats = 0
            applyingSnapshot = true
            sections = loaded.sections; parts = replacements; tempo = loaded.tempo; masterDB = loaded.masterDB
            applyingSnapshot = false; revision = UUID(); dirty = false; fileURL = url
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
        panel.title = "Save Ensemble"
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "My Ensemble.sfensemble"
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.message = "全パートの音源・設定・演奏・音量・ミュートと共通テンポをまとめて保存します。"
        if panel.runModal() == .OK, let url = panel.url { Task { await save(to: url) } }
    }
    func openPanel() {
        guard canEdit else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.sonicForgeEnsemble]; panel.canChooseDirectories = false
        panel.title = "Open Ensemble"
        if panel.runModal() == .OK, let url = panel.url { Task { await load(url) } }
    }

    func exportPanel(protecting sources: [URL] = []) {
        guard canEdit else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.title = "Export Ensemble WAV"
        panel.nameFieldStringValue = "Ensemble.wav"
        panel.message = "48 kHz · Stereo · 32-bit Float · 開始位置・音量・Mute・Releaseを反映"
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
    func reorderSection(_ id: UUID, by delta: Int) {
        guard canEdit, let index = sections.firstIndex(where: { $0.id == id }), sections.indices.contains(index + delta) else { return }
        sections.swapAt(index, index + delta)
    }
    func removeSection(_ id: UUID) {
        guard canEdit else { return }
        guard !parts.contains(where: { $0.sectionID == id }) else { error = "割り当て済みのパートをSongへ変更してから削除してください。"; return }
        sections.removeAll { $0.id == id }; error = nil
    }
    func sectionOffset(for part: EnsemblePart) -> Double { EnsembleSections.offset(part.sectionID, in: sections) }
    func maximumStart(for part: EnsemblePart) -> Double {
        guard let section = sections.first(where: { $0.id == part.sectionID }) else { return 256 }
        return max(0, min(256, section.beats - (EnsembleTimeline.repeatedLength(part.performance, count: part.repeatCount) ?? 0)))
    }
    func addSongDemo() async {
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
    func movePart(_ id: UUID, to beat: Double) {
        guard canEdit, beat.isFinite, (0...256).contains(beat), let part = parts.first(where: { $0.id == id }) else { return }
        part.startBeat = min(beat, maximumStart(for: part))
    }
    func remove(_ id: UUID) { guard canEdit else { return }; parts.removeAll { $0.id == id } }
    func setPerformance(_ document: PerformanceDocument, part id: UUID) {
        guard canEdit, let part = parts.first(where: { $0.id == id }) else { return }
        do { _ = try document.events(root: part.instrument?.root); part.performance = document; markDirty(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func loadInstrument(_ url: URL, part id: UUID) async {
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
    func addDemos(staggered: Bool = false, repeating: Bool = false) async {
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
              masterDB.isFinite, (-60...0).contains(masterDB) else { throw AudioError.invalid("パート・テンポ・音量を確認してください。") }
        try EnsembleSections.validate(sections)
        var events: [Event] = []
        for part in parts {
            guard let instrument = part.instrument else { throw AudioError.invalid("\(part.name): 楽器を割り当ててください。") }
            guard part.startBeat.isFinite, (0...256).contains(part.startBeat), part.gainDB.isFinite, (-36...0).contains(part.gainDB), instrument.envelope.isValid,
                  instrument.loop.isValid(frameCount: Int64(instrument.sample.buffer.frameLength), sampleRate: instrument.sample.buffer.format.sampleRate) else {
                throw AudioError.invalid("\(part.name): 楽器設定・音量が無効です。")
            }
            do {
                try EnsembleSections.validatePlacement(sectionID: part.sectionID, start: part.startBeat,
                    length: EnsembleTimeline.repeatedLength(part.performance, count: part.repeatCount), sections: sections)
                events += try EnsembleTimeline.events(part.performance, root: instrument.root, tempo: tempo,
                    startBeat: sectionOffset(for: part) + part.startBeat, count: part.repeatCount).map { Event(time: $0.time, part: part.id, bytes: $0.bytes) } }
            catch { throw AudioError.invalid(part.name + ": " + error.localizedDescription) }
        }
        return events.enumerated().sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }.map(\.element)
    }
    func play() {
        guard canEdit else { return }
        do {
            let events = try timeline() // Validate every part before starting any audio.
            stop()
            let engine = AVAudioEngine(); self.engine = engine
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { [meter] buffer, _ in meter.update(buffer) }
            for (index, part) in parts.enumerated() {
                let mixer = AVAudioMixerNode(); engine.attach(mixer)
                engine.connect(mixer, to: engine.mainMixerNode, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
                voices[part.id] = EnsembleVoice(instrument: part.instrument!, engine: engine, mixer: mixer)
            }
            updateGains()
            engine.prepare(); try engine.start()
            durationBeats = max((events.last?.time ?? 0) * tempo / 60, EnsembleSections.end(sections))
            playbackTempo = tempo; startedAt = ProcessInfo.processInfo.systemUptime
            playing = true; releasing = false; error = nil
            let token = generation
            task = Task { [weak self] in
                for event in events {
                    guard let self else { return }
                    do {
                        let delay = max(0, self.startedAt + event.time - ProcessInfo.processInfo.systemUptime)
                        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                        guard !Task.isCancelled, self.generation == token else { return }
                        try self.voices[event.part]?.receive(event.bytes)
                    } catch is CancellationError { return }
                    catch { self.stop(); self.error = "演奏を停止しました。\n" + error.localizedDescription; return }
                }
                guard let self, self.generation == token else { return }
                let remaining = self.startedAt + self.durationBeats * 60 / self.playbackTempo - ProcessInfo.processInfo.systemUptime
                if remaining > 0 {
                    do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
                    guard self.generation == token, !Task.isCancelled else { return }
                }
                self.releasing = true
                // Retain each part's Release tail before completing the session.
                let tailDeadline = ProcessInfo.processInfo.systemUptime + 6
                while self.voices.values.contains(where: { $0.sampler.isSounding }) && ProcessInfo.processInfo.systemUptime < tailDeadline {
                    do { try await Task.sleep(nanoseconds: 33_000_000) } catch { return }
                    guard self.generation == token else { return }
                }
                self.stop(resetPosition: false)
            }
        } catch { stop(); self.error = "同時再生を開始できませんでした。\n" + error.localizedDescription }
    }
    private func updateGains() {
        // Four-part headroom; each sampler already reserves headroom for its eight voices.
        engine?.mainMixerNode.outputVolume = Float(pow(10, max(-60, min(0, masterDB)) / 20)) / Float(Self.maximumParts)
        for part in parts { voices[part.id]?.sampler.gain = part.muted ? 0 : Float(pow(10, max(-36, min(0, part.gainDB)) / 20)) }
    }
    private func refresh() {
        guard playing else { return }
        updateGains()
        positionBeats = min(durationBeats, max(0, (ProcessInfo.processInfo.systemUptime - startedAt) * playbackTempo / 60))
        level = meter.read().max() ?? -60
        for part in parts {
            guard let voice = voices[part.id] else { continue }
            voice.sampler.refreshCompletion(); part.voices = voice.sampler.soundingCount
            part.level = voice.sampler.meter.read().max() ?? -60
        }
    }
    func stop(resetPosition: Bool = true) {
        generation = UUID(); task?.cancel(); task = nil
        voices.values.forEach { $0.stop() }; engine?.stop(); voices.removeAll(); engine = nil
        playing = false; releasing = false; level = -60
        if resetPosition { positionBeats = 0 }
        for part in parts { part.voices = 0; part.level = -60 }
    }
    func heldNotes(part id: UUID) -> Set<Int> { voices[id]?.heldNotes ?? [] }
    func pedalChannels(part id: UUID) -> Set<Int> { voices[id]?.pedalChannels ?? [] }
}
