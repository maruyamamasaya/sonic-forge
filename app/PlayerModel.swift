import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var asset: AudioAsset?
    @Published private(set) var playing = false
    @Published private(set) var loading = false
    @Published private(set) var position = 0.0
    @Published private(set) var levels: [Float] = [-60, -60]
    @Published private(set) var editor = WaveformEditor(frameCount: 1, sampleRate: 1)
    @Published private(set) var playingSelection = false
    @Published private(set) var exporting = false
    @Published private(set) var exportMessage: String?
    var busy: Bool { loading || exporting || preparingInstrument }
    @Published private(set) var preparingInstrument = false
    @Published private(set) var instrumentSample: InstrumentSample?
    @Published private(set) var activeNote: Int?
    @Published var rootNote = 60 { didSet { releaseNote(); if rootNote != oldValue && instrumentSample != nil { instrumentDirty = true } } }
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

    init() {
        instrument.onFinished = { [weak self] in self?.activeNote = nil; self?.levels = [-60, -60] }
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refreshPlaybackState() }
    }

    // Route transport keys before focused buttons consume Space. File dialogs and
    // text editors keep their normal keyboard behavior.
    func installTransportShortcuts() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = NSApp.keyWindow, window.title == "SonicForge",
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSTextView) else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard event.keyCode == 49, modifiers.isEmpty || modifiers == [.shift] else { return event }
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
        panel.title = "Export Selection"
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sonicForgeInstrument]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = instrumentFileURL?.lastPathComponent ?? URL(fileURLWithPath: sample.name).deletingPathExtension().lastPathComponent + ".sfinstrument"
        panel.title = "Save Instrument"
        panel.message = "サンプル音源と基準音をまとめて保存します。元のWAVがなくても開けます。"
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "SonicForge" && $0.isVisible }) else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.saveInstrument(sample: sample, root: root, to: url) }
        }
    }

    func saveInstrument(sample: InstrumentSample, root: Int, to url: URL, remember: Bool = true) async {
        guard !busy else { return }
        exporting = true
        defer { exporting = false }
        do {
            try await Task.detached(priority: .userInitiated) { try InstrumentDocument.save(sample: sample, rootNote: root, to: url) }.value
            instrumentFileURL = url
            instrumentDirty = false
            exportMessage = "Instrument saved · " + url.lastPathComponent
            if remember { UserDefaults.standard.set(url.path, forKey: Self.lastInstrumentKey) }
            error = nil
        } catch { self.error = "楽器を保存できませんでした。\n" + error.localizedDescription }
    }

    func openInstrumentPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sonicForgeInstrument]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open Instrument"
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
            let replacement = try AVAudioPlayer(contentsOf: restored.asset.url)
            replacement.isMeteringEnabled = true
            replacement.volume = Float(pow(10, gainDB / 20))
            guard replacement.prepareToPlay() else { throw AudioError.invalid("音声出力を準備できませんでした。") }
            stop()
            instrument.install(restored.sample)
            instrument.gain = Float(pow(10, gainDB / 20))
            player = replacement
            asset = restored.asset
            editor = WaveformEditor(frameCount: Int64(restored.sample.buffer.frameLength), sampleRate: restored.sample.buffer.format.sampleRate)
            instrumentSample = restored.sample
            rootNote = restored.rootNote
            instrumentFileURL = url
            instrumentDirty = false
            exportMessage = "Instrument opened · " + url.lastPathComponent
            if let instrumentDirectory { try? FileManager.default.removeItem(at: instrumentDirectory) }
            instrumentDirectory = restored.directory
            pendingDirectory = nil
            if remember { UserDefaults.standard.set(url.path, forKey: Self.lastInstrumentKey) }
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
            instrument.shutdown()
            instrumentSample = nil
            instrumentFileURL = nil
            instrumentDirty = false
            if let instrumentDirectory { try? FileManager.default.removeItem(at: instrumentDirectory); self.instrumentDirectory = nil }
            activeNote = nil
            selectionPlayer?.stop()
            selectionPlayer = nil
            previewSelection = nil
            playingSelection = false
            player?.stop()
            player = replacement
            exportMessage = nil
            asset = loaded
            rootNote = demo ? 57 : 60
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
        preparingInstrument = true
        defer { preparingInstrument = false }
        releaseNote()
        do {
            let sample = try await Task.detached(priority: .userInitiated) {
                try InstrumentSample.load(url: asset.url, selection: selection)
            }.value
            instrument.install(sample)
            instrument.gain = Float(pow(10, gainDB / 20))
            instrumentSample = sample
            instrumentDirty = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func playNote(_ note: Int) {
        guard !busy else { return }
        stop()
        do { try instrument.play(note: note, root: rootNote); activeNote = note }
        catch { self.error = error.localizedDescription; activeNote = nil }
    }
    func releaseNote(_ note: Int? = nil) {
        guard note == nil || activeNote == note else { return }
        instrument.stop()
        activeNote = nil
        levels = [-60, -60]
    }

    func toggle() {
        guard !busy, let player = activePlayer, asset != nil else { return }
        releaseNote()
        if player.isPlaying { player.pause(); playing = false; levels = [-60, -60] }
        else {
            if position >= playbackEnd - 0.000001 { player.currentTime = 0; position = previewOffset }
            if player.play() { playing = true } else { error = "再生できませんでした。macOSの出力デバイスを確認してください。" }
        }
    }

    func playSelection() async {
        guard !busy, let asset, let selected = editor.selection else { return }
        releaseNote()
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

    func stop() {
        releaseNote()
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
        if activeNote != nil { levels = instrument.meter.read(); return }
        guard let player = activePlayer else { return }
        if playing && !player.isPlaying {
            playing = false
            position = playbackEnd
            levels = [-60, -60]
        } else if player.isPlaying {
            position = previewOffset + player.currentTime
            player.updateMeters()
            // AVAudioPlayer metering describes source level; apply master attenuation.
            levels = (0..<2).map { max(-60, min(0, player.averagePower(forChannel: min($0, player.numberOfChannels - 1)) + Float(gainDB))) }
        }
    }
    func cleanup() {
        instrument.shutdown()
        if let instrumentDirectory { try? FileManager.default.removeItem(at: instrumentDirectory) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
        selectionPlayer?.stop()
        player?.stop()
        if let demoDirectory { try? FileManager.default.removeItem(at: demoDirectory) }
    }
}
