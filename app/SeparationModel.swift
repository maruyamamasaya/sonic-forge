import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class SeparationModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status = "曲を選んで分離してください。音源はこのMac内で処理します。"
    @Published private(set) var audio: [SeparationAudio] = []
    @Published private(set) var sourceName = ""
    @Published private(set) var previewID: String?
    @Published private(set) var previewPosition = 0.0
    @Published private(set) var previewDuration = 0.0
    @Published private(set) var error: String?
    @Published var pythonPath: String
    @Published var cachePath: String
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var control: SeparationProcess?
    private var resultLease: SeparationLease?
    private var resultDirectory: URL? { resultLease?.directory }
    private var manifest: SeparationManifest?
    private var inputExtension = ""
    private var activeDirectory: URL?
    private var generation = UUID()
    private var timer: AnyCancellable?
    var workerURL: URL { Bundle.main.resourceURL!.appendingPathComponent("separation_worker.py") }
    init() {
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        pythonPath = UserDefaults.standard.string(forKey: "separationPythonV1") ?? root.appendingPathComponent("build/separation-bench/venv/bin/python").path
        cachePath = UserDefaults.standard.string(forKey: "separationCacheV1") ?? root.appendingPathComponent("build/separation-bench/cache/mlx").path
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.previewPosition = player.currentTime
            if !player.isPlaying { self.previewID = nil }
        }
    }
    func choosePython() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "分離用Pythonを選択"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.pythonPath = url.path }
        }
    }
    func chooseCache() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.title = "分離モデルの保存先"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.cachePath = url.path }
        }
    }
    func chooseSource(onStart: @escaping () -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.wav, .mp3]
        panel.allowsMultipleSelection = false; panel.title = "分離する曲を選択"
        panel.message = "MP3 / WAV・10分以内・256 MB以下。分離はこのMac内で行います。"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in onStart(); self?.start(source: url) }
        }
    }
    func start(source: URL?, worker overrideWorker: URL? = nil) {
        guard !busy else { return }
        stopPreview(); error = nil
        UserDefaults.standard.set(pythonPath, forKey: "separationPythonV1")
        UserDefaults.standard.set(cachePath, forKey: "separationCacheV1")
        let id = UUID(); generation = id
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Separation-" + id.uuidString)
        let controller = SeparationProcess(); control = controller; activeDirectory = directory
        let python = URL(fileURLWithPath: pythonPath), cache = URL(fileURLWithPath: cachePath), worker = overrideWorker ?? workerURL
        busy = true; status = source == nil ? "モデルを準備中…（初回はダウンロードします）" : "分離の準備中…"
        task = Task { [weak self] in
            do {
                let result = try await SeparationClient().run(python: python, worker: worker, cache: cache,
                    source: source, directory: directory, jobID: id.uuidString, control: controller) { [weak self] message in
                        await self?.receive(message, id: id)
                    }
                try Task.checkCancellation()
                guard let self, self.generation == id else { try? FileManager.default.removeItem(at: directory); return }
                if source != nil {
                    self.resultLease = SeparationLease(directory); self.manifest = result
                    self.inputExtension = source!.pathExtension.lowercased(); self.audio = result.audio ?? []
                    self.sourceName = source!.lastPathComponent
                } else { try? FileManager.default.removeItem(at: directory) }
                self.status = source == nil ? "モデルの準備ができました。曲を選んで分離できます。" : "分離完了。試聴して、使いたい音を選んでください。"
            } catch {
                try? FileManager.default.removeItem(at: directory)
                guard let self, self.generation == id else { return }
                if error is CancellationError { self.status = "処理を取り消しました。前の素材は保持しています。" }
                else { self.error = error.localizedDescription; self.status = "完了しませんでした。前の素材は保持しています。" }
            }
            guard let self, self.generation == id else { return }
            self.busy = false; self.task = nil; self.control = nil; self.activeDirectory = nil
        }
    }
    private func receive(_ message: String, id: UUID) { if generation == id { status = message } }
    func cancel() { guard busy else { return }; status = "取り消し中…"; control?.terminate(); task?.cancel() }
    func url(for entry: SeparationAudio) -> URL? { resultDirectory?.appendingPathComponent(entry.file) }
    func origin(for entry: SeparationAudio) -> MaterialOrigin? {
        guard entry.id != "original", let lease = resultLease, let manifest,
              let hash = manifest.inputSHA256, let versions = manifest.versions,
              let gain = manifest.gain, let preprocessing = manifest.preprocessing else { return nil }
        return MaterialOrigin(provenance: MaterialProvenance(sourceName: sourceName, inputSHA256: hash,
            runID: manifest.jobID, model: manifest.model, backend: "mlx-metal", settings: .standard, weightSHA256: manifest.weightSHA256,
            versions: versions, gain: gain, preprocessing: preprocessing, stem: entry.id,
            frames: entry.frames, sampleRate: entry.sampleRate),
            input: lease.directory.appendingPathComponent("input." + inputExtension),
            original: lease.directory.appendingPathComponent("original.wav"),
            stem: lease.directory.appendingPathComponent(entry.file), lease: lease)
    }
    func preview(_ entry: SeparationAudio) {
        guard !busy, let url = url(for: entry) else { return }
        let position = min(previewPosition, Double(entry.frames) / entry.sampleRate)
        stopPreview(reset: false)
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.volume = 0.2; next.currentTime = position >= next.duration ? 0 : position
            guard next.prepareToPlay(), next.play() else { throw AudioError.invalid("試聴を開始できませんでした。") }
            player = next; previewID = entry.id; previewDuration = next.duration; previewPosition = next.currentTime
        } catch { self.error = error.localizedDescription }
    }
    func seekPreview(_ seconds: Double) {
        previewPosition = max(0, min(previewDuration, seconds)); player?.currentTime = previewPosition
    }
    func stopPreview(reset: Bool = true) {
        player?.stop(); player = nil; previewID = nil
        if reset { previewPosition = 0; previewDuration = 0 }
    }
    func cleanup() {
        generation = UUID(); task?.cancel(); control?.killAndWait(); stopPreview()
        if let activeDirectory { try? FileManager.default.removeItem(at: activeDirectory) }
        resultLease = nil; manifest = nil
        task = nil; control = nil; activeDirectory = nil; audio = []; busy = false
    }
}
