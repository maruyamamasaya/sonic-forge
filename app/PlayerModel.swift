import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class OutputMeterState: ObservableObject {
    @Published var levels: [Float] = [-60, -60]
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var asset: AudioAsset?
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var position = 0.0
    let outputMeter = OutputMeterState()
    private(set) var levels: [Float] {
        get { outputMeter.levels }
        set { if outputMeter.levels != newValue { outputMeter.levels = newValue } }
    }
    @Published private(set) var editor = WaveformEditor(frameCount: 1, sampleRate: 1)
    @Published private(set) var playingSelection = false
    @Published private(set) var exporting = false
    @Published private(set) var exportMessage: String?
    @Published private(set) var adoptingSeparation = false
    var busy: Bool { loading || exporting || preparingInstrument || separation.busy || adoptingSeparation || materials.busy }
    @Published private(set) var preparingInstrument = false
    @Published private(set) var instrumentSample: InstrumentSample?
    enum NoteInput: Hashable { case screen, computer, demo, midi(UInt8), midiSustain(UInt8) }
    @Published private(set) var activeNotes: Set<Int> = []
    @Published private(set) var soundingVoices = 0
    @Published var holdKeys = false { didSet { if oldValue != holdKeys { stopInstrument() } } }
    @Published private var noteInputs: [Int: Set<NoteInput>] = [:]
    @Published private(set) var sustainChannels: Set<UInt8> = []
    private var midiHistory: [UInt8: Set<Int>] = [:]
    let midi = MIDIInput()
    let library = InstrumentLibrary()
    let composer = PerformanceComposer()
    let separation = SeparationModel()
    let materials: MaterialLibraryModel
    private var materialReadLease: MaterialAudioLease?
    @Published private(set) var materialOrigin: MaterialOrigin?
    @Published private(set) var restoredMaterial: MaterialRecord?
    @Published private(set) var waveformProvenance: InstrumentProvenance?
    @Published private(set) var instrumentProvenance: InstrumentProvenance?
    var revealMaterialID: String?
    private var materialObservation: AnyCancellable?
    private var separationAssetDirectory: URL?
    @Published var ensembleWorkspaceActive = true
    let ensemble = EnsembleModel()
    @Published private(set) var midiSuspended = false
    private var computerKeys: [UInt16: Int] = [:]
    static let computerKeyboard: [UInt16: Int] = [0: 60, 13: 61, 1: 62, 14: 63, 2: 64, 3: 65, 17: 66, 5: 67, 16: 68, 4: 69, 32: 70, 38: 71, 40: 72]
    @Published var rootNote = 60 { didSet { guard NotePitch.rootRange.contains(rootNote) else { rootNote = oldValue; return }; midi.performanceRoot = rootNote; stopInstrument(); if rootNote != oldValue && instrumentSample != nil { instrumentDirty = true } } }
    @Published private(set) var sampleLoop = SampleLoop(endFrame: 2)
    func setLoop(_ value: SampleLoop) {
        guard !busy, let sample = instrumentSample,
              value.isValid(frameCount: Int64(sample.buffer.frameLength), sampleRate: sample.buffer.format.sampleRate), value != sampleLoop else { return }
        sampleLoop = value
        instrumentDirty = true
    }
    func loopFromSelection() {
        guard let sample = instrumentSample, let selection = editor.selection else { return }
        let start = selection.startFrame - sample.selection.startFrame
        let end = selection.endFrame - sample.selection.startFrame
        setLoop(SampleLoop(enabled: true, startFrame: start, endFrame: end,
                           crossfadeFrames: min(sampleLoop.crossfadeFrames, max(0, end - start) / 2)))
    }
    var canSetLoopFromSelection: Bool {
        guard let sample = instrumentSample, let selection = editor.selection else { return false }
        return selection.startFrame >= sample.selection.startFrame && selection.endFrame <= sample.selection.endFrame && selection.frameCount >= 2
    }
    @Published private(set) var envelope = ADSRParameters.standard
    func setEnvelope(_ value: ADSRParameters) {
        guard value.isValid, value != envelope, !busy else { return }
        envelope = value
        if instrumentSample != nil { instrumentDirty = true }
    }
    @Published private(set) var instrumentDirty = false
    @Published private(set) var instrumentFileURL: URL?
    private var instrumentDirectory: URL?
    private static let lastInstrumentKey = "lastInstrumentPath"
    private let instrument = SampleInstrument()
    @Published var error: String?
    @Published var gainDB = -12.0 { didSet {
        let gain = Float(pow(10, gainDB / 20))
        instrument.gain = gain
        player?.volume = gain
        selectionPlayer?.volume = gain
    } }
    private var player: AVAudioPlayer?
    private var selectionPlayer: AVAudioPlayer?
    private var previewSelection: AudioSelection?
    private var activePlayer: AVAudioPlayer? { selectionPlayer ?? player }
    private var previewOffset: Double { Double(previewSelection?.startFrame ?? 0) / editor.sampleRate }
    private var playbackEnd: Double { previewSelection.map { Double($0.endFrame) / editor.sampleRate } ?? (asset?.duration ?? 0) }
    private var keyboardMonitor: Any?
    private var timer: AnyCancellable?
    private var demoDirectory: URL?
    private var separationObservation: AnyCancellable?

    init(materialStore: MaterialStore = MaterialStore()) {
        materials = MaterialLibraryModel(store: materialStore)
        materialObservation = materials.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        separationObservation = separation.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        midi.performanceRoot = rootNote
        midi.onMessages = { [weak self] messages in self?.receiveMIDI(messages) }
        midi.onReset = { [weak self] in self?.releaseMIDI(immediate: true) }
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refreshPlaybackState() }
    }

    // Route transport keys before focused buttons consume Space. File dialogs and
    // text editors keep their normal keyboard behavior.
    func installTransportShortcuts() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyUp, let note = self.computerKeys.removeValue(forKey: event.keyCode) {
                self.releaseNote(note, input: .computer)
                return nil
            }
            guard let window = NSApp.keyWindow, window.title == "SonicForge",
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSTextView) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if self.ensembleWorkspaceActive {
                guard event.type == .keyDown, event.keyCode == 49, modifiers.isEmpty else { return event }
                if !event.isARepeat && !self.ensemble.busy {
                    if self.ensemble.playing { self.ensemble.pause() }
                    else { self.prepareEnsemblePlayback(); self.library.stopPreview(); self.ensemble.play() }
                }
                return nil
            }
            if event.type == .keyDown, modifiers.isEmpty, let note = self.computerNote(event.keyCode), self.instrumentSample != nil, !self.busy {
                if !event.isARepeat && self.computerKeys[event.keyCode] == nil {
                    self.computerKeys[event.keyCode] = note
                    self.playNote(note, input: .computer)
                }
                return nil
            }
            guard event.type == .keyDown, event.keyCode == 49, modifiers.isEmpty || modifiers == [.shift] else { return event }
            if !event.isARepeat {
                if modifiers == [.shift] { Task { await self.playSelection() } }
                else { self.toggle() }
            }
            return nil
        }
    }

    func open() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "モノラル／ステレオのWAVを選択（256 MB以下）"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.load(url) }
        }
    }

    func exportSelection() {
        guard !busy, let asset, let selection = editor.selection else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = asset.url.deletingPathExtension().lastPathComponent + "-selection.wav"
        panel.title = "選択範囲を書き出す"
        panel.message = "選択範囲を32-bit Float WAVで保存します。サンプルレート・チャンネルを維持し、Master Gainは反映しません。"
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "SonicForge" && $0.isVisible }) else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.export(asset: asset, selection: selection, to: url) }
        }
    }

    func export(asset: AudioAsset, selection: AudioSelection, to url: URL) async {
        guard !busy else { return }
        exporting = true
        exportMessage = nil
        defer { exporting = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try WAVExport.write(source: asset.url, selection: selection, to: url)
            }.value
            exportMessage = "Exported · " + url.lastPathComponent
            error = nil
        } catch { self.error = "WAVの書き出しに失敗しました。\n" + error.localizedDescription }
    }

    func startSession() async {
        await ensemble.restoreLastSession()
        midi.start()
        if let path = UserDefaults.standard.string(forKey: Self.lastInstrumentKey) {
            if await loadInstrument(URL(fileURLWithPath: path)) { return }
            let message = error
            await loadDemo()
            error = "前回の楽器を開けなかったため、デモを読み込みました。\n" + (message ?? "")
        } else { await loadDemo() }
    }

    func saveInstrumentPanel() {
        guard !busy, let sample = instrumentSample else { return }
        let root = rootNote
        let adsr = envelope
        let loop = sampleLoop
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sonicForgeInstrument]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = instrumentFileURL?.lastPathComponent ?? URL(fileURLWithPath: sample.name).deletingPathExtension().lastPathComponent + ".sfinstrument"
        panel.title = "楽器を保存"
        panel.message = "サンプル音源・基準音・ADSR・ループをまとめて保存します。元のWAVがなくても開けます。"
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "SonicForge" && $0.isVisible }) else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.saveInstrument(sample: sample, root: root, envelope: adsr, loop: loop, to: url) }
        }
    }

    func saveInstrument(sample: InstrumentSample, root: Int, envelope parameters: ADSRParameters? = nil, loop: SampleLoop? = nil, to url: URL, remember: Bool = true) async {
        guard !busy else { return }
        let adsr = parameters ?? envelope
        let loop = loop ?? sampleLoop
        let provenance = sample.buffer === instrumentSample?.buffer ? instrumentProvenance : nil
        exporting = true
        defer { exporting = false }
        do {
            if let provenance { try await materials.store.retain([MaterialProtection(record: provenance.material, label: "作成した楽器")]) }
            try await Task.detached(priority: .userInitiated) { try InstrumentDocument.save(sample: sample, rootNote: root, envelope: adsr, loop: loop, provenance: provenance, to: url) }.value
            instrumentFileURL = url
            instrumentDirty = false
            exportMessage = "Instrument saved · " + url.lastPathComponent
            if remember {
                UserDefaults.standard.set(url.path, forKey: Self.lastInstrumentKey)
                library.register(url)
            }
            error = nil
        } catch { self.error = "楽器を保存できませんでした。\n" + error.localizedDescription }
    }

    func openInstrumentPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sonicForgeInstrument]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "楽器を開く"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in _ = await self?.loadInstrument(url) }
        }
    }

    @discardableResult
    func loadInstrument(_ url: URL, remember: Bool = true) async -> Bool {
        guard !busy else { return false }
        loading = true
        defer { loading = false }
        var pendingDirectory: URL?
        do {
            let restored = try await Task.detached(priority: .userInitiated) { try InstrumentDocument.load(url) }.value
            pendingDirectory = restored.directory
            let origin: MaterialOrigin?
            if let provenance = restored.provenance {
                try? await materials.store.retain([MaterialProtection(record: provenance.material, label: "読み込んだ楽器")])
                origin = try? await materials.store.resolve(provenance)
            }
            else { origin = nil }
            let replacement = try AVAudioPlayer(contentsOf: restored.asset.url)
            replacement.isMeteringEnabled = true
            replacement.volume = Float(pow(10, gainDB / 20))
            guard replacement.prepareToPlay() else { throw AudioError.invalid("音声出力を準備できませんでした。") }
            stop()
            instrument.install(restored.sample)
            instrument.gain = Float(pow(10, gainDB / 20))
            player = replacement
            if let separationAssetDirectory { try? FileManager.default.removeItem(at: separationAssetDirectory); self.separationAssetDirectory = nil }
            materialOrigin = origin; materialReadLease = origin?.audioLease; restoredMaterial = restored.provenance?.material
            waveformProvenance = restored.provenance; instrumentProvenance = restored.provenance
            asset = restored.asset
            editor = WaveformEditor(frameCount: Int64(restored.sample.buffer.frameLength), sampleRate: restored.sample.buffer.format.sampleRate)
            instrumentSample = restored.sample
            rootNote = restored.rootNote
            envelope = restored.envelope
            sampleLoop = restored.loop
            instrumentFileURL = url
            instrumentDirty = false
            exportMessage = "Instrument opened · " + url.lastPathComponent
            if let instrumentDirectory { try? FileManager.default.removeItem(at: instrumentDirectory) }
            instrumentDirectory = restored.directory
            pendingDirectory = nil
            if remember {
                UserDefaults.standard.set(url.path, forKey: Self.lastInstrumentKey)
                library.register(url)
            }
            error = nil
            return true
        } catch {
            if let pendingDirectory { try? FileManager.default.removeItem(at: pendingDirectory) }
            self.error = "楽器を開けませんでした。\n" + error.localizedDescription
            return false
        }
    }

    func loadDemo() async {
        guard !busy else { return }
        do {
            if demoDirectory == nil {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                demoDirectory = directory
            }
            let url = demoDirectory!.appendingPathComponent("metal-hit-demo.wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                loading = true
                try await Task.detached(priority: .userInitiated) { try DemoAudio.write(to: url) }.value
                loading = false
            }
            await load(url, demo: true)
            if asset?.url == url { await prepareInstrument(useSelection: false) }
        } catch { loading = false; self.error = error.localizedDescription }
    }

    func load(_ url: URL, demo: Bool = false) async {
        guard !busy else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try AudioAsset.load(url, isDemo: demo) }.value
            let replacement = try AVAudioPlayer(contentsOf: url)
            replacement.isMeteringEnabled = true
            replacement.volume = Float(pow(10, gainDB / 20))
            guard replacement.prepareToPlay() else { throw AudioError.invalid("再生デバイスの準備ができませんでした。出力設定を確認してください。") }
            stopInstrument()
            instrument.shutdown()
            instrumentSample = nil
            instrumentFileURL = nil
            instrumentDirty = false
            if let instrumentDirectory { try? FileManager.default.removeItem(at: instrumentDirectory); self.instrumentDirectory = nil }
            activeNotes = []
            selectionPlayer?.stop()
            selectionPlayer = nil
            previewSelection = nil
            playingSelection = false
            player?.stop()
            player = replacement
            if let separationAssetDirectory { try? FileManager.default.removeItem(at: separationAssetDirectory); self.separationAssetDirectory = nil }
            exportMessage = nil
            materialOrigin = nil; materialReadLease = nil; restoredMaterial = nil
            waveformProvenance = nil; instrumentProvenance = nil
            asset = loaded
            rootNote = demo ? 57 : 60
            envelope = .standard
            editor = WaveformEditor(frameCount: Int64((loaded.duration * loaded.sampleRate).rounded()), sampleRate: loaded.sampleRate)
            playing = false
            position = 0
            levels = [-60, -60]
            error = nil
        } catch { self.error = "読み込みに失敗しました。\n" + error.localizedDescription }
    }

    func prepareInstrument(useSelection: Bool = true) async {
        guard !busy, let asset else { return }
        let selection = useSelection ? editor.selection : nil
        let origin = materialOrigin, waveform = waveformProvenance
        preparingInstrument = true
        defer { preparingInstrument = false }
        stopInstrument()
        do {
            let decoded = try await Task.detached(priority: .userInitiated) {
                try InstrumentSample.load(url: asset.url, selection: selection)
            }.value
            let sample = InstrumentSample(buffer: decoded.buffer, name: origin?.record?.name ?? waveform?.material.name ?? decoded.name, selection: decoded.selection)
            var provenance: InstrumentProvenance?
            if let origin, let record = origin.record {
                let absolute = try origin.absolute(sample.selection)
                provenance = InstrumentProvenance(material: record, startFrame: absolute.startFrame, endFrame: absolute.endFrame)
            } else if let waveform {
                guard sample.selection.endFrame <= waveform.endFrame - waveform.startFrame else { throw AudioError.invalid("楽器の来歴範囲が一致しません。") }
                provenance = InstrumentProvenance(material: waveform.material,
                    startFrame: waveform.startFrame + sample.selection.startFrame, endFrame: waveform.startFrame + sample.selection.endFrame)
            }
            try provenance?.validate(frames: Int64(sample.buffer.frameLength), sampleRate: sample.buffer.format.sampleRate)
            if let provenance { try await materials.store.retain([MaterialProtection(record: provenance.material, label: "作成した楽器")]) }
            instrument.install(sample)
            instrument.gain = Float(pow(10, gainDB / 20))
            instrumentSample = sample
            instrumentProvenance = provenance
            sampleLoop = SampleLoop(endFrame: Int64(sample.buffer.frameLength))
            instrumentDirty = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func playNote(_ note: Int, input: NoteInput = .screen, velocity: Int = 127) {
        guard (1...127).contains(velocity), !busy, instrumentSample != nil, (0...127).contains(note), (0.25...4).contains(NotePitch.rate(note: note, root: rootNote)) else { return }
        materials.stopPreview()
        ensemble.stop()
        if noteInputs[note]?.contains(input) == true { return }
        if noteInputs[note]?.isEmpty == false {
            noteInputs[note, default: []].insert(input)
            if case let .midi(channel) = input { midiHistory[channel, default: []].insert(note) }
            return
        }
        for channel in Array(midiHistory.keys) { midiHistory[channel]?.remove(note) }
        leaveSelectionPlayback()
        player?.stop(); player?.currentTime = 0; position = 0; playing = false
        do {
            try instrument.play(note: note, root: rootNote, envelope: envelope, loop: sampleLoop, velocity: velocity)
            noteInputs[note, default: []].insert(input)
            if case let .midi(channel) = input { midiHistory[channel, default: []].insert(note) }
            synchronizeNotes()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func releaseNote(_ note: Int? = nil, input: NoteInput = .screen) {
        guard let note else {
            noteInputs.removeAll(); computerKeys.removeAll(); sustainChannels.removeAll(); instrument.noteOff(); synchronizeNotes(); return
        }
        guard noteInputs[note]?.remove(input) != nil else { return }
        if noteInputs[note]?.isEmpty == true { noteInputs.removeValue(forKey: note); instrument.noteOff(note) }
        synchronizeNotes()
    }
    private func midiNoteOff(_ note: Int, channel: UInt8) {
        guard noteInputs[note]?.contains(.midi(channel)) == true else { return }
        if sustainChannels.contains(channel) { noteInputs[note, default: []].insert(.midiSustain(channel)) }
        releaseNote(note, input: .midi(channel))
    }
    private func setMIDISustain(_ channel: UInt8, down: Bool) {
        if down { if !sustainChannels.contains(channel) { sustainChannels.insert(channel) } }
        else {
            if sustainChannels.contains(channel) { sustainChannels.remove(channel) }
            for note in Array(noteInputs.keys) { releaseNote(note, input: .midiSustain(channel)) }
        }
    }
    func receiveMIDI(_ messages: [MIDIMessage]) {
        for message in messages {
            switch message.kind {
            case let .on(velocity):
                guard !midiSuspended else { continue }
                if let application = NSApp, application.modalWindow != nil || application.keyWindow?.attachedSheet != nil { continue }
                releaseNote(message.note, input: .midiSustain(message.channel))
                releaseNote(message.note, input: .midi(message.channel))
                playNote(message.note, input: .midi(message.channel), velocity: velocity)
            case .off: midiNoteOff(message.note, channel: message.channel)
            case .allOff:
                for note in Array(noteInputs.keys) { midiNoteOff(note, channel: message.channel) }
            case let .sustain(down):
                if !midiSuspended || !down { setMIDISustain(message.channel, down: down) }
            case .resetControllers: setMIDISustain(message.channel, down: false)
            case .silence: releaseMIDI(channel: message.channel, immediate: true)
            }
        }
    }
    private func releaseMIDI(channel: UInt8? = nil, immediate: Bool) {
        let history = midiHistory.filter { channel == nil || $0.key == channel }.values.reduce(into: Set<Int>()) { $0.formUnion($1) }
        for note in Set(noteInputs.keys).union(history) {
            let inputs = noteInputs[note] ?? []
            for input in inputs {
                let inputChannel: UInt8?
                switch input {
                case let .midi(value), let .midiSustain(value): inputChannel = value
                default: inputChannel = nil
                }
                if let inputChannel, channel == nil || channel == inputChannel { releaseNote(note, input: input) }
            }
            if immediate && noteInputs[note] == nil { instrument.stopNote(note) }
        }
        if immediate {
            if let channel { sustainChannels.remove(channel) } else { sustainChannels.removeAll() }
            for key in Array(midiHistory.keys) where channel == nil || key == channel { midiHistory.removeValue(forKey: key) }
        }
        synchronizeNotes()
    }
    func suspendMIDI(_ suspended: Bool) {
        if midiSuspended != suspended { midiSuspended = suspended }
        if suspended { stopInstrument() }
    }
    func screenKeyDown(_ note: Int) {
        if holdKeys && noteInputs[note]?.contains(.screen) == true { releaseNote(note) }
        else { playNote(note) }
    }
    func screenKeyUp(_ note: Int) { if !holdKeys { releaseNote(note) } }
    var demoChordActive: Bool { noteInputs.values.contains { $0.contains(.demo) } }
    func computerNote(_ key: UInt16) -> Int? {
        Self.computerKeyboard[key].map { $0 - 60 + NotePitch.computerBase(root: rootNote) }
    }
    func toggleDemoChord() {
        if demoChordActive {
            for note in Array(noteInputs.keys) { releaseNote(note, input: .demo) }
        } else {
            let base = rootNote
            for note in [base, base + 4, base + 7] { playNote(note, input: .demo) }
        }
    }
    private func synchronizeNotes() {
        instrument.refreshCompletion()
        let held = instrument.heldNotes
        for note in Array(noteInputs.keys) where !held.contains(note) { noteInputs.removeValue(forKey: note) }
        if activeNotes != held { activeNotes = held }
        let count = instrument.soundingCount
        if soundingVoices != count { soundingVoices = count }
    }
    func stopInstrument() {
        materials.stopPreview()
        separation.stopPreview()
        ensemble.stop()
        instrument.stop()
        midi.cancelTestState()
        midiHistory.removeAll()
        sustainChannels.removeAll()
        noteInputs.removeAll(); computerKeys.removeAll()
        activeNotes = []; soundingVoices = 0
        levels = [-60, -60]
    }

    func toggle() {
        guard !busy, let player = activePlayer, asset != nil else { return }
        stopInstrument()
        if player.isPlaying { player.pause(); playing = false; levels = [-60, -60] }
        else {
            if position >= playbackEnd - 0.000001 { player.currentTime = 0; position = previewOffset }
            if player.play() { playing = true } else { error = "再生できませんでした。macOSの出力デバイスを確認してください。" }
        }
    }

    func playSelection() async {
        guard !busy, let asset, let selected = editor.selection else { return }
        stopInstrument()
        loading = true
        defer { loading = false }
        leaveSelectionPlayback()
        player?.pause()
        selectionPlayer?.stop()
        selectionPlayer = nil
        previewSelection = nil
        playing = false
        playingSelection = false
        levels = [-60, -60]
        do {
            if demoDirectory == nil {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                demoDirectory = directory
            }
            let url = demoDirectory!.appendingPathComponent("selection.caf")
            try await Task.detached(priority: .userInitiated) {
                try SelectionAudio.write(source: asset.url, selection: selected, to: url)
            }.value
            let preview = try AVAudioPlayer(contentsOf: url)
            preview.isMeteringEnabled = true
            preview.volume = Float(pow(10, gainDB / 20))
            guard preview.prepareToPlay(), preview.play() else {
                throw AudioError.invalid("選択範囲を再生できませんでした。出力設定を確認してください。")
            }
            selectionPlayer = preview
            previewSelection = selected
            playingSelection = true
            playing = true
            position = Double(selected.startFrame) / editor.sampleRate
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func leaveSelectionPlayback() {
        guard selectionPlayer != nil else { return }
        selectionPlayer?.stop()
        selectionPlayer = nil
        previewSelection = nil
        playingSelection = false
        playing = false
        levels = [-60, -60]
        player?.currentTime = position
    }
    func select(from a: Double, to b: Double) {
        guard !busy, asset != nil else { return }
        leaveSelectionPlayback()
        exportMessage = nil
        editor.select(from: a, to: b)
    }
    func clearSelection() {
        guard !busy else { return }
        leaveSelectionPlayback()
        editor.clearSelection()
    }
    func zoom(by multiplier: Double) {
        guard !busy, let asset else { return }
        let center = editor.selectionRange.map { ($0.lowerBound + $0.upperBound) / 2 } ?? (position / asset.duration)
        editor.setZoom(editor.zoom * multiplier, around: center)
    }
    func fitAll() { editor.setZoom(1, around: 0.5) }
    func fitSelection() { editor.fitSelection() }
    func pan(to center: Double) { editor.pan(to: center) }

    /// Stop Sample Studio audio without losing the ensemble audition cursor.
    func prepareEnsemblePlayback() {
        let beat = ensemble.positionBeats
        stop()
        ensemble.seek(to: beat)
    }

    func stop() {
        stopInstrument()
        leaveSelectionPlayback()
        player?.stop(); player?.currentTime = 0; position = 0; playing = false; levels = [-60, -60]
    }
    func seek(_ fraction: Double) {
        guard !busy, let asset else { return }
        leaveSelectionPlayback()
        position = max(0, min(1, fraction)) * asset.duration
        player?.currentTime = position
    }
    func refreshPlaybackState() {
        synchronizeNotes()
        if instrument.isSounding { levels = instrument.meter.read(); return }
        guard let player = activePlayer else { levels = [-60, -60]; return }
        if playing && !player.isPlaying {
            playing = false
            position = playbackEnd
            levels = [-60, -60]
        } else if player.isPlaying {
            position = previewOffset + player.currentTime
            player.updateMeters()
            // AVAudioPlayer metering describes source level; apply master attenuation.
            levels = (0..<2).map { max(-60, min(0, player.averagePower(forChannel: min($0, player.numberOfChannels - 1)) + Float(gainDB))) }
        } else { levels = [-60, -60] }
    }
    func cleanup() {
        materials.cancel(); materialOrigin = nil; materialReadLease = nil
        separation.cleanup()
        if let separationAssetDirectory { try? FileManager.default.removeItem(at: separationAssetDirectory) }
        ensemble.stop()
        library.stopPreview()
        composer.cancel()
        midi.close()
        instrument.shutdown()
        if let instrumentDirectory { try? FileManager.default.removeItem(at: instrumentDirectory) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
        selectionPlayer?.stop()
        player?.stop()
        if let demoDirectory { try? FileManager.default.removeItem(at: demoDirectory) }
    }
}


extension PlayerModel {
    func useSeparatedAudio(_ source: URL, origin: MaterialOrigin? = nil) async -> Bool {
        guard !busy else { return false }
        adoptingSeparation = true
        defer { adoptingSeparation = false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-SeparatedSample-" + UUID().uuidString)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: source, to: destination) }.value
            adoptingSeparation = false
            await load(destination)
            guard asset?.url == destination else { try? FileManager.default.removeItem(at: directory); return false }
            separationAssetDirectory = directory
            materialOrigin = origin
            return true
        } catch {
            try? FileManager.default.removeItem(at: directory)
            self.error = "選んだ音を開けませんでした。" + error.localizedDescription
            return false
        }
    }
    func saveBeforeSeparationUse() async -> Bool {
        guard !busy, let sample = instrumentSample else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sonicForgeInstrument]
        panel.nameFieldStringValue = instrumentFileURL?.lastPathComponent ?? "楽器.sfinstrument"
        panel.title = "編集中の楽器を保存"
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return false }
        await saveInstrument(sample: sample, root: rootNote, to: url)
        return !instrumentDirty && instrumentFileURL == url
    }
}

extension PlayerModel {
    var materialSelectionInSource: AudioSelection? {
        guard let origin = materialOrigin, let selection = editor.selection else { return nil }
        return try? origin.absolute(selection)
    }
    var canSaveMaterial: Bool {
        guard let origin = materialOrigin, let selection = editor.selection, let asset else { return false }
        return asset.sampleRate == origin.provenance.sampleRate && selection.frameCount > 0 && selection.frameCount <= 30 * 44100
    }
    func prepareMaterial(name: String) {
        guard !busy, canSaveMaterial, let origin = materialOrigin, let selection = editor.selection else { return }
        stop(); ensemble.stop(); library.stopPreview(); separation.stopPreview()
        materials.prepare(origin: origin, selection: selection, name: name)
    }
    @discardableResult
    func openMaterial(_ id: String, original: Bool = false, clip: Bool = false) async -> Bool {
        guard !busy else { return false }
        adoptingSeparation = true
        defer { adoptingSeparation = false }
        do {
            let restored = try await materials.store.restore(id)
            let url = original ? restored.origin.original : clip ? restored.clip : restored.origin.stem
            adoptingSeparation = false
            await load(url)
            guard asset?.url == url, error == nil else { return false }
            // Clip coordinates are local; the origin offset is applied exactly once on save.
            editor.select(from: Double(restored.record.startFrame) / Double(restored.record.provenance.frames),
                          to: Double(restored.record.endFrame) / Double(restored.record.provenance.frames))
            var origin = restored.origin
            if clip && !original {
                origin.frameOffset = restored.record.startFrame
                editor.select(from: 0, to: 1)
                waveformProvenance = InstrumentProvenance(material: restored.record, startFrame: restored.record.startFrame, endFrame: restored.record.endFrame)
            }
            position = clip && !original ? 0 : Double(restored.record.startFrame) / restored.record.provenance.sampleRate
            player?.currentTime = position
            materialReadLease = origin.audioLease
            materialOrigin = original ? nil : origin
            restoredMaterial = restored.record
            exportMessage = "素材を復元 · " + restored.record.name
            return true
        } catch {
            self.error = "素材を開けませんでした。\n" + error.localizedDescription
            return false
        }
    }
}

extension PlayerModel {
    func previewMaterial(_ kind: MaterialPreviewKind) {
        guard !busy else { return }
        if materials.previewDuration == 0 {
            stop(); library.stopPreview()
        }
        materials.preview(kind)
    }
}

extension PlayerModel {
    var materialDeletionProtections: [MaterialProtection] {
        ensemble.materialProtections + (instrumentProvenance.map { [MaterialProtection(record: $0.material, label: "編集中の楽器")] } ?? [])
    }
    var materialDeletionFiles: [URL] {
        library.entries.map(\.url) + (instrumentFileURL.map { [$0] } ?? []) + (ensemble.fileURL.map { [$0] } ?? [])
    }
}
