import Foundation
import AVFoundation

enum EnsembleExportTests {
    @MainActor static func run() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Mix-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = EnsembleModel(); await model.addDemos(staggered: true)
        model.tempo = 240
        // Short, looped note with explicit pedal and Release after the note ends.
        var performance = model.parts[0].performance
        performance.notes = [PerformanceNote(beat: 0, duration: 0.5, pitch: 57, velocity: 100, channel: 0)]
        performance.pedals = [PerformancePedal(beat: 0, down: true, channel: 0), PerformancePedal(beat: 1, down: false, channel: 0)]
        model.setPerformance(performance, part: model.parts[0].id)
        model.setPerformance(performance, part: model.parts[1].id)
        model.parts[0].startBeat = 1; model.parts[1].startBeat = 2
        model.parts[1].muted = true
        let snapshot = try model.snapshot()
        let url = dir.appendingPathComponent("mix.wav")
        try await EnsembleExport.write(snapshot, to: url)
        let asset = try AudioAsset.load(url)
        let audio = try AVAudioFile(forReading: url)
        precondition(audio.processingFormat.sampleRate == 48000 && audio.processingFormat.channelCount == 2)
        let data = try InstrumentSample.load(url: url).buffer
        func energy(_ buffer: AVAudioPCMBuffer, _ start: Double, _ end: Double) -> Double {
            let a = Int(start * 48000), b = min(Int(buffer.frameLength), Int(end * 48000))
            return (a..<b).reduce(0) { $0 + pow(Double(buffer.floatChannelData![0][$1]), 2) }
        }
        precondition(energy(data, 0, 0.24) < 1e-10)
        precondition(energy(data, 0.3, 0.45) > 1e-8)
        precondition(energy(data, 0.52, 0.7) > 1e-8) // Pedal off at .5, then Release.
        precondition(energy(data, asset.duration - 0.03, asset.duration) < 1e-9)
        model.parts[0].gainDB = -6; model.masterDB -= 6
        let quiet = dir.appendingPathComponent("quiet.wav")
        try await EnsembleExport.write(try model.snapshot(), to: quiet)
        let quietData = try InstrumentSample.load(url: quiet).buffer
        let ratio = energy(quietData, 0.3, 0.45) / energy(data, 0.3, 0.45)
        precondition(abs(ratio - pow(10, -12.0 / 10)) < 0.002)
        model.parts[0].muted = true
        let silent = dir.appendingPathComponent("silent.wav")
        try await EnsembleExport.write(try model.snapshot(), to: silent)
        let silentData = try InstrumentSample.load(url: silent).buffer
        precondition(energy(silentData, 0, asset.duration) < 1e-12)
        let original = try Data(contentsOf: url)
        do { try await EnsembleExport.write(snapshot, to: url, protecting: [url]); fatalError("Source overwritten") } catch {}
        for name in ["symlink.wav", "hardlink.wav"] {
            let alias = dir.appendingPathComponent(name)
            if name.hasPrefix("sym") { try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url) }
            else { try FileManager.default.linkItem(at: url, to: alias) }
            do { try await EnsembleExport.write(snapshot, to: alias, protecting: [url]); fatalError("Alias overwritten") } catch {}
        }
        model.tempo = 40; model.parts[0].startBeat = 256
        var longPerformance = performance; longPerformance.notes[0].duration = 255
        longPerformance.pedals = []
        model.setPerformance(longPerformance, part: model.parts[0].id)
        do { try await EnsembleExport.write(try model.snapshot(), to: url); fatalError("Oversize accepted") } catch {}
        let task = Task { @MainActor in
            try await EnsembleExport.write(snapshot, to: url, progress: { _ in })
        }
        task.cancel()
        do { try await task.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        let after = try Data(contentsOf: url); precondition(after == original)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        precondition(!leftovers.contains { $0.hasPrefix(".sonicforge-ensemble-") })
        model.tempo = 240; model.parts[0].startBeat = 1
        model.setPerformance(performance, part: model.parts[0].id)
        let exported = await model.exportWAV(to: quiet)
        precondition(exported && !model.busy && !model.exporting && model.exportedURL == quiet)
        let player = PlayerModel(); await player.load(url)
        precondition(player.asset != nil && abs(player.asset!.duration - asset.duration) < 0.001)
        print("PASS: ensemble WAV stereo/48k export/reimport, delayed silence, pedal/Release tail, gain/master ratio, mute, cancellation and source protection")
    }
}
