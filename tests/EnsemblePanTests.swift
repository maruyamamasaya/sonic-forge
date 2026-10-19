import Foundation
import AVFoundation

@MainActor
enum EnsemblePanTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Pan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for channels in [1, 2] {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels))!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            buffer.frameLength = 4800
            for channel in 0..<channels {
                for frame in 0..<4800 {
                    buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 48000) * (channel == 0 ? 0.3 : 0.15))
                }
            }
            let instrument = EnsembleInstrument(sample: InstrumentSample(buffer: buffer, name: "Pan demo", selection: AudioSelection(startFrame: 0, endFrame: 4800)), root: 57,
                envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.08),
                loop: SampleLoop(enabled: true, endFrame: 4800), name: "Pan demo")
            let performance = PerformanceDocument(name: "Held", notes: [.init(beat: 0, duration: 1, pitch: 57, velocity: 100)], pedals: [])
            let model = EnsembleModel(); let part = model.addPart(instrument: instrument, performance: performance)!
            model.tempo = 240
            func render(_ pan: Double, muted: Bool = false) async throws -> [Double] {
                part.pan = pan; part.muted = muted
                let file = directory.appendingPathComponent("\(channels)-\(pan)-\(muted).wav")
                try await EnsembleExport.write(model.snapshot(), to: file)
                let audio = try AudioAsset.load(file); precondition(audio.duration > 0.3)
                let output = try InstrumentSample.load(url: file).buffer
                precondition(output.format.channelCount == 2)
                return (0..<2).map { channel in
                    (2400..<9600).reduce(0) { $0 + pow(Double(output.floatChannelData![channel][$1]), 2) }
                }
            }
            let center = try await render(0), left = try await render(-1), right = try await render(1)
            print("Pan energies channels=\(channels): center=\(center), left=\(left), right=\(right)")
            precondition(center.allSatisfy { $0 > 1e-7 })
            precondition(left[0] > 1e-7 && left[1] < left[0] * 1e-8)
            precondition(right[1] > 1e-7 && right[0] < right[1] * 1e-8)
            let halfLeft = try await render(-0.5), halfRight = try await render(0.5)
            precondition(halfLeft[0] / halfLeft[1] > center[0] / center[1])
            precondition(halfRight[0] / halfRight[1] < center[0] / center[1])
            let silent = try await render(1, muted: true); precondition(silent.allSatisfy { $0 < 1e-12 })
            part.muted = false; part.pan = -0.65
            let file = directory.appendingPathComponent("pan-\(channels).sfensemble")
            let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            precondition(object["version"] as! Int == 11)
            let restored = EnsembleModel(); let opened = await restored.load(file, remember: false)
            precondition(opened && restored.parts[0].pan == -0.65)
            part.pan = 0.75
            precondition(model.dirty && model.restoreSongEdit() && part.pan == -0.65)
            precondition(model.restoreSongEdit(redo: true) && part.pan == 0.75)
            // AI arrangement proposals preserve this manual mix setting.
            let brief = try model.arrangementBrief(prompt: "サビで厚く")
            let proposal = try ArrangementGeneration.demo(brief)
            let materialized = try ArrangementGeneration.materialize(proposal, brief: brief)
            precondition(materialized.parts[0].pan == 0.75 && model.applyArrangement(proposal, brief: brief) && part.pan == 0.75)
            for version in 1...5 {
                var legacy = object; legacy["version"] = version
                var parts = legacy["parts"] as! [[String: Any]]; parts[0].removeValue(forKey: "pan"); legacy["parts"] = parts
                let url = directory.appendingPathComponent("legacy-\(version).sfensemble")
                try JSONSerialization.data(withJSONObject: legacy).write(to: url)
                let old = try EnsembleDocument.load(url); precondition(old.parts[0].pan == 0)
            }
            let originalIDs = restored.parts.map(\.id)
            for bad: Any in [2.0, -2.0, "left", NSNull()] {
                var invalid = object, parts = object["parts"] as! [[String: Any]]
                parts[0]["pan"] = bad; invalid["parts"] = parts
                let url = directory.appendingPathComponent("invalid.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: url)
                let accepted = await restored.load(url, remember: false)
                precondition(!accepted && restored.parts.map(\.id) == originalIDs && restored.parts[0].pan == -0.65)
            }
            var missing = object, archiveParts = object["parts"] as! [[String: Any]]
            archiveParts[0].removeValue(forKey: "pan"); missing["parts"] = archiveParts
            let invalidFile = directory.appendingPathComponent("missing.sfensemble")
            try JSONSerialization.data(withJSONObject: missing).write(to: invalidFile)
            let accepted = await restored.load(invalidFile, remember: false); precondition(!accepted)
            for invalid in [Double.nan, Double.infinity, -1.01, 1.01] {
                part.pan = invalid
                do { _ = try model.snapshot(); fatalError("Invalid pan accepted") } catch {}
                do { _ = try model.timeline(); fatalError("Invalid pan played") } catch {}
                let failed = await model.save(to: file, remember: false); precondition(!failed)
                let retained = try EnsembleDocument.load(file); precondition(retained.parts[0].pan == -0.65)
            }
        }
        print("PASS: mono/stereo pan left/right/center/intermediate and mute in production WAV; v6 save/restore, v1-v5 center migration, atomic rejection, undo/redo and AI preservation")
    }
}
