import Foundation
import AVFoundation

@MainActor
enum EnsembleDelayTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Delay-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        precondition(PartDelay.off.tailSeconds == 0)
        precondition(PartDelay(timeMS: 1000, mix: 100, feedback: 60).tailSeconds <= 15)
        for channels in [1, 2] {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels))!
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            pcm.frameLength = 4800
            for channel in 0..<channels {
                for frame in 0..<4800 {
                    pcm.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 1000 / 48000) * 0.2 * (channel == 0 ? 1 : 0.5))
                }
            }
            let instrument = EnsembleInstrument(sample: InstrumentSample(buffer: pcm, name: "Echo pulse", selection: AudioSelection(startFrame: 0, endFrame: 4800)), root: 57,
                envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0), loop: SampleLoop(endFrame: 4800), name: "Echo pulse")
            let model = EnsembleModel()
            let part = model.addPart(instrument: instrument, performance: PerformanceDocument(name: "Pulse", notes: [.init(beat: 0, duration: 0.04, pitch: 57, velocity: 100)], pedals: []))!
            model.tempo = 240
            var serial = 0
            func render(_ settings: PartDelay) async throws -> AVAudioPCMBuffer {
                part.delay = settings; serial += 1
                let url = directory.appendingPathComponent("echo-\(channels)-\(serial).wav")
                try await EnsembleExport.write(model.snapshot(), to: url)
                return try InstrumentSample.load(url: url).buffer
            }
            func energy(_ buffer: AVAudioPCMBuffer, _ start: Double, _ end: Double, channel: Int = 0) -> Double {
                let a = min(Int(start * 48000), Int(buffer.frameLength)), b = min(Int(end * 48000), Int(buffer.frameLength))
                return (a..<b).reduce(0.0) { $0 + pow(Double(buffer.floatChannelData![channel][$1]), 2) }
            }
            let settings = PartDelay(timeMS: 250, mix: 50, feedback: 40)
            let dry = try await render(.off), echo = try await render(settings)
            precondition(abs(Double(echo.frameLength - dry.frameLength) / 48000 - settings.tailSeconds) < 0.0001)
            let first = energy(echo, 0.245, 0.28), second = energy(echo, 0.495, 0.53)
            precondition(first > 1e-7 && second > first * 0.1 && second < first * 0.25)
            precondition(energy(echo, 0.1, 0.2) < first * 1e-5)
            let tailEnd = Double(echo.frameLength) / 48000
            precondition(energy(echo, tailEnd - 0.05, tailEnd) < first * 1e-5)
            let single = try await render(PartDelay(timeMS: 250, mix: 50, feedback: 0))
            precondition(energy(single, 0.245, 0.28) > 1e-7 && energy(single, 0.495, 0.53) < 1e-12)
            let faster = try await render(PartDelay(timeMS: 100, mix: 50, feedback: 0))
            precondition(energy(faster, 0.095, 0.13) > 1e-7 && energy(faster, 0.245, 0.28) < 1e-12)
            let quieterEcho = try await render(PartDelay(timeMS: 250, mix: 25, feedback: 40))
            let mixRatio = energy(quieterEcho, 0.245, 0.28) / first
            precondition(mixRatio > 0.2 && mixRatio < 0.6)
            let reset = try await render(.off)
            precondition(reset.frameLength == dry.frameLength)
            precondition((0..<Int(dry.frameLength)).allSatisfy { abs(reset.floatChannelData![0][$0] - dry.floatChannelData![0][$0]) < 1e-7 })
            part.gainDB = -6
            let quiet = try await render(settings)
            precondition(abs(energy(quiet, 0.245, 0.28) / first - pow(10, -6.0 / 10)) < 0.01)
            part.gainDB = 0; part.pan = -1
            let left = try await render(settings)
            precondition(energy(left, 0, 3, channel: 1) < 1e-12)
            part.pan = 0; part.muted = true
            let mute = try await render(settings); precondition(energy(mute, 0, 3) < 1e-12)
            part.muted = false; part.reverb = 35; part.eq = PartEQ(lowDB: 2, midDB: -1, highDB: 3)
            let combined = try await render(settings)
            precondition(combined.frameLength - echo.frameLength == 144000)
            precondition(energy(combined, 0.3, 0.45) > 1e-8)
            let other = model.addPart(instrument: instrument, performance: part.performance)!
            other.delay = PartDelay(timeMS: 400, mix: 20, feedback: 0)
            let file = directory.appendingPathComponent("delay.sfensemble")
            let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
            let original = try Data(contentsOf: file)
            let object = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            precondition(object["version"] as! Int == 11)
            let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
            precondition(loaded && restored.parts.map(\.delay) == [settings, other.delay])
            var off = settings; off.mix = 0; part.delay = off
            precondition(model.dirty && model.restoreSongEdit() && part.delay == settings)
            precondition(model.restoreSongEdit(redo: true) && part.delay == off)
            part.delay = settings
            let brief = try model.arrangementBrief(prompt: "サビで厚く")
            let proposal = try ArrangementGeneration.demo(brief), preview = try ArrangementGeneration.materialize(proposal, brief: brief)
            precondition(preview.parts.map(\.delay) == [settings, other.delay])
            precondition(model.applyArrangement(proposal, brief: brief) && part.delay == settings)
            for version in 1...8 {
                var legacy = object, parts = object["parts"] as! [[String: Any]]
                for index in parts.indices { parts[index].removeValue(forKey: "delay") }
                legacy["parts"] = parts; legacy["version"] = version
                let url = directory.appendingPathComponent("legacy.sfensemble")
                try JSONSerialization.data(withJSONObject: legacy).write(to: url)
                let old = try EnsembleDocument.load(url); precondition(old.parts.allSatisfy { $0.delay == .off })
            }
            let ids = restored.parts.map(\.id)
            for bad: Any in [NSNull(), "echo", ["timeMS": 49, "mix": 25, "feedback": 35], ["timeMS": 250, "mix": 101, "feedback": 35], ["timeMS": 250, "mix": 25, "feedback": 61], ["timeMS": 250, "mix": 25]] {
                var invalid = object, parts = object["parts"] as! [[String: Any]]
                parts[1]["delay"] = bad; invalid["parts"] = parts
                let url = directory.appendingPathComponent("bad.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: url)
                let accepted = await restored.load(url, remember: false)
                precondition(!accepted && restored.parts.map(\.id) == ids && restored.parts[0].delay == settings)
            }
            var missing = object, parts = object["parts"] as! [[String: Any]]
            parts[1].removeValue(forKey: "delay"); missing["parts"] = parts
            let url = directory.appendingPathComponent("missing.sfensemble")
            try JSONSerialization.data(withJSONObject: missing).write(to: url)
            let accepted = await restored.load(url, remember: false); precondition(!accepted)
            for path in [\PartDelay.timeMS, \.mix, \.feedback] {
                for value in [Double.nan, Double.infinity, -1, 1001] {
                    var invalid = settings; invalid[keyPath: path] = value; part.delay = invalid
                    do { _ = try model.snapshot(); fatalError("Invalid delay saved") } catch {}
                    do { _ = try model.timeline(); fatalError("Invalid delay played") } catch {}
                    let saved = await model.save(to: file, remember: false); precondition(!saved)
                }
            }
            let preserved = try Data(contentsOf: file); precondition(preserved == original)
        }
        if CommandLine.arguments.contains("--playback") {
            let model = EnsembleModel(); await model.addDemos(delayed: true); model.tempo = 240
            precondition(model.parts.map(\.delay.timeMS) == [350, 250])
            model.play(); try await Task.sleep(nanoseconds: 180_000_000)
            precondition(model.playing)
            model.parts[0].delay = PartDelay(timeMS: 200, mix: 40, feedback: 30)
            model.parts[1].muted = true
            for _ in 0..<50 {
                if model.parts[1].level <= -59 { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            precondition(model.parts[1].level <= -59)
            model.stop(); precondition(!model.playing && model.parts.allSatisfy { $0.voices == 0 && $0.level == -60 })
        }
        print("PASS: delay mono/stereo echo timing, feedback/mix, OFF, tails, EQ/reverb/pan/gain/mute, v9/legacy persistence, atomic rejection, history and AI retention")
    }
}
