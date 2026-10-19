import Foundation
import AVFoundation

@MainActor
enum EnsembleCompressorTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Compressor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = PartCompressor(enabled: true, thresholdDB: -30, headroomDB: 1, attackMS: 1, releaseMS: 50)
        for channels in [1, 2] {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels))!
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000)!
            pcm.frameLength = 96000
            for channel in 0..<channels {
                for frame in 0..<96000 {
                    let amplitude = (frame / 24000).isMultiple(of: 2) ? 0.04 : 0.8
                    pcm.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 1000 / 48000) * amplitude * (channel == 0 ? 1 : 0.5))
                }
            }
            let instrument = EnsembleInstrument(sample: InstrumentSample(buffer: pcm, name: "Dynamic tone", selection: AudioSelection(startFrame: 0, endFrame: 96000)), root: 57,
                envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0), loop: SampleLoop(endFrame: 96000), name: "Dynamic tone")
            let model = EnsembleModel()
            let part = model.addPart(instrument: instrument, performance: PerformanceDocument(name: "Dynamics", notes: [.init(beat: 0, duration: 4, pitch: 57, velocity: 127)], pedals: []))!
            model.tempo = 120
            var serial = 0
            func render(_ value: PartCompressor) async throws -> AVAudioPCMBuffer {
                part.compressor = value; serial += 1
                let file = directory.appendingPathComponent("compression-\(channels)-\(serial).wav")
                try await EnsembleExport.write(model.snapshot(), to: file)
                return try InstrumentSample.load(url: file).buffer
            }
            func energy(_ buffer: AVAudioPCMBuffer, _ start: Double = 0.3, _ end: Double = 0.4, channel: Int = 0) -> Double {
                let a = Int(start * 48000), b = min(Int(end * 48000), Int(buffer.frameLength))
                return (a..<b).reduce(0) { $0 + pow(Double(buffer.floatChannelData![channel][$1]), 2) }
            }
            let dry = try await render(.off), compressed = try await render(settings)
            let quietDry = energy(dry), loudDry = energy(dry, 0.8, 0.9)
            let quietCompressed = energy(compressed), loudCompressed = energy(compressed, 0.8, 0.9)
            precondition(quietDry > 1e-9 && loudCompressed > 1e-9)
            precondition(loudCompressed < loudDry * 0.8, "Loud peaks must be reduced")
            precondition(loudCompressed / quietCompressed < loudDry / quietDry * 0.8, "Dynamic range must shrink")
            precondition(compressed.frameLength == dry.frameLength)
            var relaxed = settings; relaxed.headroomDB = 30
            let lessCompression = try await render(relaxed)
            precondition(energy(lessCompression, 0.8, 0.9) > loudCompressed * 1.1)
            relaxed = settings; relaxed.thresholdDB = 0
            let highThreshold = try await render(relaxed)
            precondition(energy(highThreshold, 0.8, 0.9) > loudCompressed * 1.1)
            relaxed = settings; relaxed.attackMS = 200
            let slowAttack = try await render(relaxed)
            precondition(energy(slowAttack, 0.502, 0.52) > energy(compressed, 0.502, 0.52) * 1.1)
            relaxed = settings; relaxed.releaseMS = 3000
            let slowRelease = try await render(relaxed)
            precondition(energy(slowRelease, 1.3, 1.4) < energy(compressed, 1.3, 1.4) * 0.9)
            var boosted = settings; boosted.makeupDB = 6
            let makeup = try await render(boosted)
            precondition(abs(energy(makeup, 0.8, 0.9) / loudCompressed - pow(10, 6.0 / 10)) < 0.1)
            var bypass = boosted; bypass.enabled = false
            let reset = try await render(bypass)
            precondition((0..<Int(dry.frameLength)).allSatisfy { abs(reset.floatChannelData![0][$0] - dry.floatChannelData![0][$0]) < 1e-7 })
            part.pan = -1
            let left = try await render(settings); precondition(energy(left, 0, 2, channel: 1) < 1e-12)
            part.pan = 0; part.gainDB = -6
            let quiet = try await render(settings)
            precondition(abs(energy(quiet, 0.8, 0.9) / loudCompressed - pow(10, -6.0 / 10)) < 0.01)
            part.gainDB = 0; part.muted = true
            let mute = try await render(settings); precondition(energy(mute, 0, 2) < 1e-12)
            part.muted = false
            let other = model.addPart(instrument: instrument, performance: part.performance)!
            other.compressor = boosted
            let url = directory.appendingPathComponent("compressor.sfensemble")
            let saved = await model.save(to: url, remember: false); precondition(saved && !model.dirty)
            let original = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            precondition(object["version"] as! Int == 11)
            let restored = EnsembleModel(); let loaded = await restored.load(url, remember: false)
            precondition(loaded && restored.parts.map(\.compressor) == [settings, boosted] && !restored.playing)
            part.compressor = bypass
            precondition(model.dirty && model.restoreSongEdit() && part.compressor == settings)
            precondition(model.restoreSongEdit(redo: true) && part.compressor == bypass)
            part.compressor = settings
            let brief = try model.arrangementBrief(prompt: "サビで厚く"), proposal = try ArrangementGeneration.demo(brief)
            let preview = try ArrangementGeneration.materialize(proposal, brief: brief)
            precondition(preview.parts.map(\.compressor) == [settings, boosted])
            precondition(model.applyArrangement(proposal, brief: brief) && part.compressor == settings)
            for version in 1...9 {
                var old = object, parts = object["parts"] as! [[String: Any]]
                for index in parts.indices { parts[index].removeValue(forKey: "compressor") }
                old["parts"] = parts; old["version"] = version
                let legacy = directory.appendingPathComponent("legacy.sfensemble")
                try JSONSerialization.data(withJSONObject: old).write(to: legacy)
                let read = try EnsembleDocument.load(legacy); precondition(read.parts.allSatisfy { $0.compressor == .off })
            }
            let ids = restored.parts.map(\.id)
            let badValues: [Any] = [NSNull(), "bad", ["enabled": true],
                ["enabled": true, "thresholdDB": -41, "headroomDB": 5, "attackMS": 10, "releaseMS": 150, "makeupDB": 0]]
            for bad in badValues {
                var invalid = object, parts = object["parts"] as! [[String: Any]]
                parts[1]["compressor"] = bad; invalid["parts"] = parts
                let file = directory.appendingPathComponent("invalid.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: file)
                let accepted = await restored.load(file, remember: false)
                precondition(!accepted && restored.parts.map(\.id) == ids && restored.parts[0].compressor == settings)
            }
            for key in ["compressor", "enabled", "thresholdDB", "headroomDB", "attackMS", "releaseMS", "makeupDB"] {
                var invalid = object, parts = object["parts"] as! [[String: Any]]
                if key == "compressor" { parts[1].removeValue(forKey: key) }
                else {
                    var settings = parts[1]["compressor"] as! [String: Any]
                    settings.removeValue(forKey: key); parts[1]["compressor"] = settings
                }
                invalid["parts"] = parts
                let file = directory.appendingPathComponent("missing.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: file)
                let accepted = await restored.load(file, remember: false)
                precondition(!accepted && restored.parts.map(\.id) == ids)
            }
            for path in [\PartCompressor.thresholdDB, \.headroomDB, \.attackMS, \.releaseMS, \.makeupDB] {
                for value in [Double.nan, Double.infinity, -100, 4000] {
                    var invalid = settings; invalid[keyPath: path] = value; part.compressor = invalid
                    do { _ = try model.snapshot(); fatalError("Invalid compressor saved") } catch {}
                    do { _ = try model.timeline(); fatalError("Invalid compressor played") } catch {}
                    let saved = await model.save(to: url, remember: false); precondition(!saved)
                }
            }
            let preserved = try Data(contentsOf: url); precondition(preserved == original)
        }
        let demo = EnsembleModel(); await demo.addDemos(compressed: true)
        precondition(demo.parts.count == 2 && demo.parts.allSatisfy { $0.compressor.enabled })
        precondition(Set(demo.parts[1].performance.notes.map(\.velocity)) == [45, 120])
        let file = directory.appendingPathComponent("demo.wav")
        try await EnsembleExport.write(demo.snapshot(), to: file)
        let audio = try InstrumentSample.load(url: file); precondition(audio.buffer.frameLength > 0)
        if CommandLine.arguments.contains("--playback") {
            demo.play(); try await Task.sleep(nanoseconds: 200_000_000)
            precondition(demo.playing)
            demo.parts[0].compressor.makeupDB = 3
            demo.parts[1].compressor.enabled = false
            try await Task.sleep(nanoseconds: 200_000_000)
            precondition(demo.parts.contains { $0.level > -59 })
            demo.stop(); precondition(!demo.playing && demo.parts.allSatisfy { $0.voices == 0 && $0.level == -60 })
        }
        print("PASS: compressor mono/stereo dynamic range, makeup, bypass, gain/pan/mute, v10/legacy persistence, rejection, history, AI, demo WAV reload")
    }
}
