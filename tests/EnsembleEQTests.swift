import Foundation
import AVFoundation

@MainActor
enum EnsembleEQTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-EQ-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let frequencies = [60.0, 1000, 12000]
        for channels in [1, 2] {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels))!
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            pcm.frameLength = 4800
            for channel in 0..<channels {
                for frame in 0..<4800 {
                    pcm.floatChannelData![channel][frame] = Float(frequencies.reduce(0) {
                        $0 + sin(Double(frame) * 2 * .pi * $1 / 48000) * 0.03
                    } * (channel == 0 ? 1 : 0.5))
                }
            }
            let instrument = EnsembleInstrument(sample: InstrumentSample(buffer: pcm, name: "EQ tones", selection: AudioSelection(startFrame: 0, endFrame: 4800)), root: 57,
                envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.05), loop: SampleLoop(enabled: true, endFrame: 4800), name: "EQ tones")
            let model = EnsembleModel()
            let part = model.addPart(instrument: instrument, performance: PerformanceDocument(name: "Held", notes: [.init(beat: 0, duration: 4, pitch: 57, velocity: 100)], pedals: []))!
            model.tempo = 240
            var serial = 0
            func render(_ settings: PartEQ) async throws -> AVAudioPCMBuffer {
                part.eq = settings; serial += 1
                let url = directory.appendingPathComponent("tone-\(channels)-\(serial).wav")
                try await EnsembleExport.write(model.snapshot(), to: url)
                return try InstrumentSample.load(url: url).buffer
            }
            func amplitudes(_ buffer: AVAudioPCMBuffer, channel: Int = 0) -> [Double] {
                frequencies.map { frequency in
                    var sine = 0.0, cosine = 0.0
                    for frame in 9600..<24000 {
                        let angle = Double(frame) * 2 * .pi * frequency / 48000
                        let value = Double(buffer.floatChannelData![channel][frame])
                        sine += value * sin(angle); cosine += value * cos(angle)
                    }
                    return hypot(sine, cosine) * 2 / 14400
                }
            }
            let flat = try await render(.flat), baseline = amplitudes(flat)
            precondition(baseline.allSatisfy { $0 > 1e-5 })
            let paths: [WritableKeyPath<PartEQ, Double>] = [\.lowDB, \.midDB, \.highDB]
            for band in 0..<3 {
                for gain in [-6.0, 6.0] {
                    var eq = PartEQ.flat; eq[keyPath: paths[band]] = gain
                    let output = try await render(eq), changed = amplitudes(output)
                    let db = zip(changed, baseline).map { 20 * log10($0 / $1) }
                    precondition(gain > 0 ? db[band] > 4 : db[band] < -4)
                    for other in 0..<3 where other != band { precondition(abs(db[other]) < 2) }
                    if channels == 2 {
                        let right = amplitudes(output, channel: 1)
                        precondition(zip(changed, right).allSatisfy { abs($0 / $1 - 2) < 0.01 })
                    }
                }
            }
            let reset = try await render(.flat)
            precondition(zip(amplitudes(reset), baseline).allSatisfy { abs($0 / $1 - 1) < 1e-5 })
            let settings = PartEQ(lowDB: 4, midDB: -3, highDB: 6)
            part.pan = -1
            let panned = try await render(settings)
            let rightEnergy = (9600..<24000).reduce(0.0) { $0 + pow(Double(panned.floatChannelData![1][$1]), 2) }
            precondition(rightEnergy < 1e-12)
            part.pan = 0; part.muted = true
            let silent = try await render(settings)
            precondition(amplitudes(silent).allSatisfy { $0 < 1e-12 })
            part.muted = false
            let file = directory.appendingPathComponent("eq-\(channels).sfensemble")
            let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            precondition(object["version"] as! Int == 7)
            let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
            precondition(loaded && restored.parts[0].eq == settings)
            part.eq = .flat
            precondition(model.dirty && model.restoreSongEdit() && part.eq == settings)
            precondition(model.restoreSongEdit(redo: true) && part.eq == .flat)
            part.eq = settings
            let brief = try model.arrangementBrief(prompt: "サビで厚く")
            let proposal = try ArrangementGeneration.demo(brief)
            let preview = try ArrangementGeneration.materialize(proposal, brief: brief)
            precondition(preview.parts[0].eq == settings && model.applyArrangement(proposal, brief: brief) && part.eq == settings)
            for version in 1...6 {
                var old = object, parts = object["parts"] as! [[String: Any]]
                parts[0].removeValue(forKey: "eq"); old["parts"] = parts; old["version"] = version
                let url = directory.appendingPathComponent("old-\(version).sfensemble")
                try JSONSerialization.data(withJSONObject: old).write(to: url)
                let legacy = try EnsembleDocument.load(url); precondition(legacy.parts[0].eq == .flat)
            }
            let ids = restored.parts.map(\.id)
            for bad: Any in [NSNull(), "bright", ["lowDB": 13, "midDB": 0, "highDB": 0], ["lowDB": 0, "midDB": 0]] {
                var invalid = object, parts = object["parts"] as! [[String: Any]]
                parts[0]["eq"] = bad; invalid["parts"] = parts
                let url = directory.appendingPathComponent("bad.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: url)
                let accepted = await restored.load(url, remember: false)
                precondition(!accepted && restored.parts.map(\.id) == ids && restored.parts[0].eq == settings)
            }
            var missing = object, parts = object["parts"] as! [[String: Any]]
            parts[0].removeValue(forKey: "eq"); missing["parts"] = parts
            let url = directory.appendingPathComponent("missing.sfensemble")
            try JSONSerialization.data(withJSONObject: missing).write(to: url)
            let accepted = await restored.load(url, remember: false); precondition(!accepted)
            for path in paths {
                for value in [Double.nan, Double.infinity, -12.01, 12.01] {
                    var invalid = settings; invalid[keyPath: path] = value; part.eq = invalid
                    do { _ = try model.snapshot(); fatalError("Invalid EQ saved") } catch {}
                    do { _ = try model.timeline(); fatalError("Invalid EQ played") } catch {}
                    let saved = await model.save(to: file, remember: false); precondition(!saved)
                }
            }
            let unchanged = try EnsembleDocument.load(file); precondition(unchanged.parts[0].eq == settings)
        }
        print("PASS: production three-band EQ frequency gain/cut, flat reset, mono/stereo balance, pan/mute, v7 persistence, v1-v6 migration, atomic rejection, undo/redo and AI preservation")
    }
}
