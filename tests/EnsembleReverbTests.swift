import Foundation
import AVFoundation

@MainActor
enum EnsembleReverbTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Reverb-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for channels in [1, 2] {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels))!
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            pcm.frameLength = 4800
            for channel in 0..<channels {
                for frame in 0..<4800 {
                    pcm.floatChannelData![channel][frame] = Float((sin(Double(frame) * 2 * .pi * 440 / 48000) + sin(Double(frame) * 2 * .pi * 1733 / 48000)) * 0.2 * (channel == 0 ? 1 : 0.5))
                }
            }
            let instrument = EnsembleInstrument(sample: InstrumentSample(buffer: pcm, name: "Room pulse", selection: AudioSelection(startFrame: 0, endFrame: 4800)), root: 57,
                envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0), loop: SampleLoop(endFrame: 4800), name: "Room pulse")
            let model = EnsembleModel()
            let part = model.addPart(instrument: instrument, performance: PerformanceDocument(name: "Pulse", notes: [.init(beat: 0, duration: 0.2, pitch: 57, velocity: 100)], pedals: []))!
            model.tempo = 240
            var serial = 0
            func render(_ amount: Double) async throws -> AVAudioPCMBuffer {
                part.reverb = amount; serial += 1
                let url = directory.appendingPathComponent("room-\(channels)-\(serial).wav")
                try await EnsembleExport.write(model.snapshot(), to: url)
                return try InstrumentSample.load(url: url).buffer
            }
            func energy(_ buffer: AVAudioPCMBuffer, _ start: Double, _ end: Double, channel: Int = 0) -> Double {
                let range = Int(start * 48000)..<min(Int(end * 48000), Int(buffer.frameLength))
                return range.reduce(0.0) { $0 + pow(Double(buffer.floatChannelData![channel][$1]), 2) }
            }
            let dry = try await render(0), wet = try await render(45), wetter = try await render(90)
            precondition(Int(wet.frameLength) - Int(dry.frameLength) == 144000)
            let tail = energy(wet, 0.12, 0.7), strongTail = energy(wetter, 0.12, 0.7)
            precondition(tail > 1e-7 && strongTail > tail * 1.8 && strongTail < tail * 2.2)
            precondition(energy(wet, 2.9, 3.05) < tail * 0.001)
            let reset = try await render(0)
            precondition(reset.frameLength == dry.frameLength)
            precondition((0..<Int(dry.frameLength)).allSatisfy { abs(dry.floatChannelData![0][$0] - reset.floatChannelData![0][$0]) < 1e-7 })
            part.gainDB = -6
            let quiet = try await render(45)
            precondition(abs(energy(quiet, 0.12, 0.7) / tail - pow(10, -6.0 / 10)) < 0.01)
            part.gainDB = 0; part.pan = -1
            let left = try await render(45)
            precondition(energy(left, 0, 3, channel: 1) < 1e-12)
            part.pan = 0; part.muted = true
            let mute = try await render(45)
            precondition(energy(mute, 0, 3) < 1e-12)
            part.muted = false; part.reverb = 35
            let other = model.addPart(instrument: instrument, performance: part.performance)!
            other.reverb = 15
            let file = directory.appendingPathComponent("room.sfensemble")
            let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
            let original = try Data(contentsOf: file)
            let object = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            precondition(object["version"] as! Int == 11)
            let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
            precondition(loaded && restored.parts.map(\.reverb) == [35, 15])
            part.reverb = 0
            precondition(model.dirty && model.restoreSongEdit() && part.reverb == 35 && other.reverb == 15)
            precondition(model.restoreSongEdit(redo: true) && part.reverb == 0)
            part.reverb = 35
            let brief = try model.arrangementBrief(prompt: "イントロは薄く")
            let proposal = try ArrangementGeneration.demo(brief)
            let preview = try ArrangementGeneration.materialize(proposal, brief: brief)
            precondition(preview.parts.map(\.reverb) == [35, 15])
            precondition(model.applyArrangement(proposal, brief: brief) && part.reverb == 35 && other.reverb == 15)
            for version in 1...7 {
                var old = object, parts = object["parts"] as! [[String: Any]]
                for index in parts.indices { parts[index].removeValue(forKey: "reverb") }
                old["parts"] = parts; old["version"] = version
                let url = directory.appendingPathComponent("legacy.sfensemble")
                try JSONSerialization.data(withJSONObject: old).write(to: url)
                let legacy = try EnsembleDocument.load(url)
                precondition(legacy.parts.allSatisfy { $0.reverb == 0 })
            }
            let ids = restored.parts.map(\.id)
            for bad: Any in [NSNull(), "room", -1, 101] {
                var invalid = object, parts = object["parts"] as! [[String: Any]]
                parts[1]["reverb"] = bad; invalid["parts"] = parts
                let url = directory.appendingPathComponent("bad.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: url)
                let accepted = await restored.load(url, remember: false)
                precondition(!accepted && restored.parts.map(\.id) == ids && restored.parts.map(\.reverb) == [35, 15])
            }
            var missing = object, parts = object["parts"] as! [[String: Any]]
            parts[1].removeValue(forKey: "reverb"); missing["parts"] = parts
            let url = directory.appendingPathComponent("missing.sfensemble")
            try JSONSerialization.data(withJSONObject: missing).write(to: url)
            let accepted = await restored.load(url, remember: false); precondition(!accepted)
            for value in [Double.nan, Double.infinity, -0.01, 100.01] {
                part.reverb = value
                do { _ = try model.snapshot(); fatalError("Invalid room saved") } catch {}
                do { _ = try model.timeline(); fatalError("Invalid room played") } catch {}
                let saved = await model.save(to: file, remember: false); precondition(!saved)
            }
            let preserved = try Data(contentsOf: file)
            precondition(preserved == original)
        }
        if CommandLine.arguments.contains("--playback") {
            let model = EnsembleModel(); await model.addDemos(reverberant: true)
            model.tempo = 240
            precondition(model.parts.map(\.reverb) == [35, 15])
            model.play(); try await Task.sleep(nanoseconds: 150_000_000)
            precondition(model.playing)
            model.parts[0].reverb = 60; model.parts[1].muted = true
            // Device/tap buffers and the 30 Hz UI clock can exceed 100 ms.
            for _ in 0..<50 {
                if model.parts[1].level <= -59 { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            precondition(model.parts[1].level <= -59)
            model.stop(); precondition(!model.playing && model.parts.allSatisfy { $0.voices == 0 && $0.level == -60 })
        }
        print("PASS: reverb mono/stereo tail/amount/off, pan/mute/gain, v8 persistence, v1-v7 migration, rejection, history, AI retention and demo")
    }
}
