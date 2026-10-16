import AppKit
import AVFoundation
import Combine

struct LibraryEntry: Identifiable, Equatable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var available: Bool { FileManager.default.fileExists(atPath: url.path) }
}

@MainActor
final class InstrumentLibrary: ObservableObject {
    @Published private(set) var entries: [LibraryEntry] = []
    @Published var query = ""
    @Published private(set) var busy = false
    @Published private(set) var previewing: URL?
    @Published private(set) var previewDescription: String?
    @Published var error: String?
    private let defaults: UserDefaults
    private let directory: URL
    private let key = "instrumentLibraryPathsV1"
    private var engine: SampleInstrument?
    var previewLevels: [Float] { engine?.meter.read() ?? [-60, -60] }
    private var previewDirectory: URL?
    private var previewTask: Task<Void, Never>?
    private var generation = UUID()

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SonicForge/Library", isDirectory: true)
        entries = Array(Set(defaults.stringArray(forKey: key) ?? []))
            .map { LibraryEntry(url: URL(fileURLWithPath: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var filtered: [LibraryEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { term.isEmpty || $0.name.localizedStandardContains(term) }
    }
    func register(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !entries.contains(where: { $0.url == normalized }) else { return }
        entries.append(LibraryEntry(url: normalized))
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        defaults.set(entries.map { $0.url.path }, forKey: key)
    }
    func remove(_ entry: LibraryEntry) {
        stopPreview()
        entries.removeAll { $0.id == entry.id }
        defaults.set(entries.map { $0.url.path }, forKey: key)
    }
    func addPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sonicForgeInstrument]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        Task { await add(panel.urls) }
    }
    func add(_ urls: [URL]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        stopPreview()
        var failures: [String] = []
        for url in urls {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let restored = try InstrumentDocument.load(url)
                    try? FileManager.default.removeItem(at: restored.directory)
                }.value
                register(url)
            } catch { failures.append(url.lastPathComponent + ": " + error.localizedDescription) }
        }
        error = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
    func addDemos() async {
        guard !busy else { return }
        busy = true
        stopPreview()
        defer { busy = false }
        let directory = self.directory
        do {
            let urls = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let wav = temporary.appendingPathComponent("demo.wav")
                try DemoAudio.write(to: wav)
                let sample = try InstrumentSample.load(url: wav, selection: AudioSelection(startFrame: 0, endFrame: 96000))
                var result: [URL] = []
                for (name, adsr) in [("Demo — Metal", ADSRParameters.standard),
                                     ("Demo — Soft", ADSRParameters(attack: 0.3, decay: 0.4, sustain: 0.6, release: 0.8))] {
                    let url = directory.appendingPathComponent(name + ".sfinstrument")
                    // Never overwrite an existing library file, including user edits.
                    if !FileManager.default.fileExists(atPath: url.path) {
                        try InstrumentDocument.save(sample: sample, rootNote: 57, envelope: adsr, to: url)
                    }
                    let restored = try InstrumentDocument.load(url)
                    try? FileManager.default.removeItem(at: restored.directory)
                    result.append(url)
                }
                return result
            }.value
            urls.forEach { register($0) }
            error = nil
        } catch { self.error = "デモ楽器を追加できませんでした。\n" + error.localizedDescription }
    }
    func preview(_ entry: LibraryEntry) async {
        guard !busy else { return }
        stopPreview()
        busy = true
        let token = generation
        defer { busy = false }
        do {
            let restored = try await Task.detached(priority: .userInitiated) { try InstrumentDocument.load(entry.url) }.value
            guard token == generation else {
                try? FileManager.default.removeItem(at: restored.directory)
                return
            }
            previewDirectory = restored.directory
            let engine = SampleInstrument()
            self.engine = engine
            engine.install(restored.sample)
            engine.gain = Float(pow(10, -18.0 / 20))
            try engine.play(note: restored.rootNote, root: restored.rootNote, envelope: restored.envelope, loop: restored.loop, velocity: 100)
            previewing = entry.url
            previewDescription = "\(NotePitch.name(restored.rootNote)) · \(timeLabel(restored.asset.duration)) · \(restored.loop.enabled ? "Loop" : "One-shot")"
            error = nil
            previewTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.engine?.noteOff()
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled, self.generation == token else { return }
                self.stopPreview()
            }
        } catch {
            stopPreview()
            self.error = "試聴できませんでした。\n" + error.localizedDescription
        }
    }
    func stopPreview() {
        generation = UUID()
        previewTask?.cancel()
        previewTask = nil
        engine?.shutdown()
        engine = nil
        previewing = nil
        previewDescription = nil
        if let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
        previewDirectory = nil
    }
}
