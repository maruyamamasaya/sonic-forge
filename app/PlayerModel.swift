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
    @Published var error: String?
    @Published var gainDB = -12.0 { didSet { player?.volume = Float(pow(10, gainDB / 20)) } }
    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?
    private var demoDirectory: URL?

    init() {
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
    }

    func open() {
        guard !loading else { return }
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

    func loadDemo() async {
        guard !loading else { return }
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
        } catch { loading = false; self.error = error.localizedDescription }
    }

    func load(_ url: URL, demo: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try AudioAsset.load(url, isDemo: demo) }.value
            let replacement = try AVAudioPlayer(contentsOf: url)
            replacement.isMeteringEnabled = true
            replacement.volume = Float(pow(10, gainDB / 20))
            guard replacement.prepareToPlay() else { throw AudioError.invalid("再生デバイスの準備ができませんでした。出力設定を確認してください。") }
            player?.stop()
            player = replacement
            asset = loaded
            playing = false
            position = 0
            levels = [-60, -60]
            error = nil
        } catch { self.error = "読み込みに失敗しました。\n" + error.localizedDescription }
    }

    func toggle() {
        guard !loading, let player, let asset else { return }
        if player.isPlaying { player.pause(); playing = false; levels = [-60, -60] }
        else {
            if position >= asset.duration - 0.01 { player.currentTime = 0 }
            if player.play() { playing = true } else { error = "再生できませんでした。macOSの出力デバイスを確認してください。" }
        }
    }

    func stop() { player?.stop(); player?.currentTime = 0; position = 0; playing = false; levels = [-60, -60] }
    func seek(_ fraction: Double) {
        guard !loading, let asset else { return }
        position = max(0, min(1, fraction)) * asset.duration
        player?.currentTime = position
    }
    private func tick() {
        guard let player else { return }
        if playing && !player.isPlaying {
            playing = false
            position = asset?.duration ?? 0
            levels = [-60, -60]
        } else if player.isPlaying {
            position = player.currentTime
            player.updateMeters()
            // AVAudioPlayer metering describes source level; apply master attenuation.
            levels = (0..<2).map { max(-60, min(0, player.averagePower(forChannel: min($0, player.numberOfChannels - 1)) + Float(gainDB))) }
        }
    }
    func cleanup() {
        player?.stop()
        if let demoDirectory { try? FileManager.default.removeItem(at: demoDirectory) }
    }
}
