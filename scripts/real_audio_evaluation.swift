import Foundation
import AVFoundation

/// Local evaluation only: uses production material/archive/sampler/export paths.
@main struct RealAudioEvaluation {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let split = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let input = URL(fileURLWithPath: CommandLine.arguments[3])
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: split.appendingPathComponent("manifest.json"))) as! [String: Any]
        let configs = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("candidates.json"))) as! [[String: Any]]
        let store = MaterialStore(root: output.appendingPathComponent("isolated-library"))
        let run = UUID().uuidString
        for config in configs {
            let stem = config["stem"] as! String, root = config["root"] as! Int
            let a = config["startFrame"] as! Int64, b = config["endFrame"] as! Int64
            let selection = AudioSelection(startFrame: a, endFrame: b)
            let stemURL = split.appendingPathComponent(stem + ".wav")
            let source = try AVAudioFile(forReading: stemURL)
            let p = MaterialProvenance(sourceName: input.lastPathComponent, inputSHA256: manifest["inputSHA256"] as! String,
                runID: run, model: "htdemucs", backend: "mlx-metal", settings: .standard,
                weightSHA256: manifest["weightSHA256"] as! String, versions: manifest["versions"] as! [String: String],
                gain: manifest["gain"] as! Double, preprocessing: "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1",
                stem: stem, frames: source.length, sampleRate: 44100)
            let draft = try await store.prepare(origin: MaterialOrigin(provenance: p, input: input,
                original: split.appendingPathComponent("original.wav"), stem: stemURL, lease: nil), selection: selection, name: "Real evaluation " + stem)
            let record = try await store.commit(draft.id)
            let sample = try InstrumentSample.load(url: stemURL, selection: selection)
            let origin = InstrumentProvenance(material: record, startFrame: a, endFrame: b)
            let frames = Int64(sample.buffer.frameLength)
            let envelope = ADSRParameters(attack: 0.005, decay: 0.05, sustain: 0.8, release: 0.12)
            let loop = SampleLoop(enabled: stem != "drums", startFrame: frames / 4, endFrame: frames, crossfadeFrames: min(882, frames / 8))
            let archive = output.appendingPathComponent(stem + ".sfinstrument")
            try InstrumentDocument.save(sample: sample, rootNote: root, envelope: envelope, loop: loop, provenance: origin, to: archive)
            let instrument = try EnsembleInstrument.load(archive)
            precondition(instrument.provenance == origin)
            for (label, offsets) in [("pitch_m12", [-12]), ("pitch_root", [0]), ("pitch_p12", [12]), ("chord", [0,4,7]), ("phrase", [0,4,7,12,7,4,2,0]), ("loop_hard", [0]), ("loop_crossfade", [0])] {
                let phrase = label == "phrase"
                let notes = offsets.enumerated().map { i, offset in
                    PerformanceNote(beat: phrase ? Double(i) * 0.5 : 0, duration: phrase ? 0.4 : 2, pitch: root + offset, velocity: phrase ? [65,85,100,75][i % 4] : 90)
                }
                let performance = PerformanceDocument(name: label, tempo: 120, notes: notes, pedals: [])
                var settings = instrument
                if label.hasPrefix("loop_") {
                    var changed = loop; changed.enabled = true
                    if label == "loop_hard" { changed.crossfadeFrames = 0 }
                    settings = EnsembleInstrument(sample: instrument.sample, root: root, envelope: envelope, loop: changed, name: instrument.name, provenance: origin)
                }
                let snapshot = EnsembleSnapshot(tempo: 120, masterDB: 0, parts: [EnsemblePartSnapshot(name: stem, instrument: settings, performance: performance, gainDB: 0, muted: false)])
                let url = output.appendingPathComponent(stem + "_" + label + ".wav")
                try await EnsembleExport.write(snapshot, to: url, protecting: [input, stemURL])
                let checked = try AudioAsset.load(url)
                precondition(checked.duration > 0)
                if phrase {
                    let song = output.appendingPathComponent(stem + "_phrase.sfensemble")
                    try EnsembleDocument.save(snapshot, to: song)
                    let restored = try EnsembleDocument.load(song)
                    precondition(restored.parts[0].instrument.provenance == origin && restored.parts[0].performance == performance)
                }
            }
            print("PASS: real " + stem + " material, v5 instrument, pitch/chord/phrase/loop render, v12 composition and WAV reload")
        }
    }
}
