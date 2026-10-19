import Foundation
import AVFoundation

@MainActor
enum MasterLimiterTests {
    static func run() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Limiter-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for channels in [1, 2] {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels))!
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000)!
            pcm.frameLength = 96000
            for channel in 0..<channels {
                for frame in 0..<96000 {
                    let amplitude = (frame % 24000 < 1200) ? 0.95 : 0.15
                    pcm.floatChannelData![channel][frame] = Float(amplitude * sin(Double(frame) * 2 * .pi * 1000 / 48000) * (channel == 0 ? 1 : 0.5))
                }
            }
            let instrument = EnsembleInstrument(sample: InstrumentSample(buffer: pcm, name: "Peak test", selection: AudioSelection(startFrame: 0, endFrame: 96000)), root: 57,
                envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.05), loop: SampleLoop(endFrame: 96000), name: "Peak test")
            let model = EnsembleModel(); model.masterDB = 0
            for _ in 0..<4 {
                let p = model.addPart(instrument: instrument, performance: PerformanceDocument(name: "Peaks", notes: [.init(beat: 0, duration: 3, pitch: 57, velocity: 127)], pedals: []))!
                p.eq = PartEQ(lowDB: 6, midDB: 6, highDB: 6)
                p.compressor = PartCompressor(enabled: true, thresholdDB: 0, headroomDB: 40, makeupDB: 24)
            }
            var serial = 0
            func render(_ limiter: MasterLimiter) async throws -> AVAudioPCMBuffer {
                model.limiter = limiter; serial += 1
                let url = dir.appendingPathComponent("limit-\(channels)-\(serial).wav")
                try await EnsembleExport.write(model.snapshot(), to: url)
                return try InstrumentSample.load(url: url).buffer
            }
            func peak(_ buffer: AVAudioPCMBuffer, channel: Int = 0) -> Float {
                (0..<Int(buffer.frameLength)).reduce(0) { max($0, abs(buffer.floatChannelData![channel][$1])) }
            }
            func energy(_ buffer: AVAudioPCMBuffer) -> Double {
                (0..<Int(buffer.frameLength)).reduce(0) { $0 + pow(Double(buffer.floatChannelData![0][$1]), 2) }
            }
            let dry = try await render(.off); precondition(peak(dry) > 1, "Fixture must overload the master")
            for ceiling in [-0.1, -1.0, -6, -12] {
                for release in [1.0, 24, 60] {
                    let limited = try await render(MasterLimiter(enabled: true, ceilingDB: ceiling, releaseMS: release))
                    let bound = Float(pow(10, ceiling / 20))
                    precondition(peak(limited) <= bound + 0.002 && peak(limited) > bound * 0.2, "Limiter exceeded ceiling")
                    precondition(peak(limited, channel: 1) <= bound + 0.002)
                    precondition(limited.frameLength == dry.frameLength && energy(limited) < energy(dry))
                }
            }
            var bypass = MasterLimiter(enabled: true, ceilingDB: -6, releaseMS: 60); bypass.enabled = false
            let reset = try await render(bypass)
            precondition((0..<Int(dry.frameLength)).allSatisfy { abs(reset.floatChannelData![0][$0] - dry.floatChannelData![0][$0]) < 1e-7 })
            for p in model.parts { p.muted = true }
            let silence = try await render(.standard); precondition(peak(silence) < 1e-12)
            for p in model.parts { p.muted = false; p.pan = -1; p.delay = PartDelay(timeMS: 100, mix: 20, feedback: 20); p.reverb = 20 }
            let effects = try await render(.standard)
            precondition(peak(effects) <= Float(pow(10, -1.0 / 20)) + 0.002 && peak(effects, channel: 1) < 1e-12)
            model.masterDB = -60
            let quiet = try await render(.standard); precondition(peak(quiet) < 0.02)
            model.masterDB = -12
            let settings = MasterLimiter(enabled: true, ceilingDB: -2, releaseMS: 40)
            model.limiter = settings
            let file = dir.appendingPathComponent("limiter.sfensemble")
            let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
            let data = try Data(contentsOf: file), object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            precondition(object["version"] as! Int == 11)
            let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
            precondition(loaded && restored.limiter == settings && !restored.playing)
            model.limiter.enabled = false
            precondition(model.dirty && model.restoreSongEdit() && model.limiter == settings)
            precondition(model.restoreSongEdit(redo: true) && !model.limiter.enabled)
            model.limiter = settings
            let brief = try model.arrangementBrief(prompt: "サビで厚く"), proposal = try ArrangementGeneration.demo(brief)
            let preview = try ArrangementGeneration.materialize(proposal, brief: brief)
            precondition(preview.limiter == settings && model.applyArrangement(proposal, brief: brief) && model.limiter == settings)
            for version in 1...10 {
                var old = object; old.removeValue(forKey: "limiter"); old["version"] = version
                let url = dir.appendingPathComponent("legacy.sfensemble")
                try JSONSerialization.data(withJSONObject: old).write(to: url)
                let read = try EnsembleDocument.load(url); precondition(read.limiter == .off)
            }
            let ids = restored.parts.map(\.id)
            for bad: Any in [NSNull(), "bad", ["enabled": true], ["enabled": true, "ceilingDB": 0, "releaseMS": 24], ["enabled": true, "ceilingDB": -1, "releaseMS": 61]] {
                var invalid = object; invalid["limiter"] = bad
                let url = dir.appendingPathComponent("invalid.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: url)
                let accepted = await restored.load(url, remember: false)
                precondition(!accepted && restored.limiter == settings && restored.parts.map(\.id) == ids)
            }
            for key in ["limiter", "enabled", "ceilingDB", "releaseMS"] {
                var invalid = object
                if key == "limiter" { invalid.removeValue(forKey: key) }
                else { var value = invalid["limiter"] as! [String: Any]; value.removeValue(forKey: key); invalid["limiter"] = value }
                let url = dir.appendingPathComponent("missing.sfensemble")
                try JSONSerialization.data(withJSONObject: invalid).write(to: url)
                let accepted = await restored.load(url, remember: false); precondition(!accepted && restored.limiter == settings)
            }
            for path in [\MasterLimiter.ceilingDB, \.releaseMS] {
                for value in [Double.nan, Double.infinity, -100, 1000] {
                    var invalid = settings; invalid[keyPath: path] = value; model.limiter = invalid
                    do { _ = try model.snapshot(); fatalError("Invalid limiter saved") } catch {}
                    do { _ = try model.timeline(); fatalError("Invalid limiter played") } catch {}
                    let saved = await model.save(to: file, remember: false); precondition(!saved)
                }
            }
            let preserved = try Data(contentsOf: file); precondition(preserved == data)
        }
        let demo = EnsembleModel(); await demo.addDemos(limited: true)
        precondition(demo.parts.count == 2 && demo.limiter == .standard && demo.masterDB == 0)
        let demoFile = dir.appendingPathComponent("demo.wav")
        try await EnsembleExport.write(demo.snapshot(), to: demoFile)
        let sample = try InstrumentSample.load(url: demoFile)
        let peak = (0..<Int(sample.buffer.frameLength)).reduce(Float(0)) { max($0, abs(sample.buffer.floatChannelData![0][$1])) }
        precondition(peak > 0.01 && peak <= Float(pow(10, -1.0 / 20)) + 0.002)
        demo.limiter.enabled = false
        let dryFile = dir.appendingPathComponent("demo-off.wav")
        try await EnsembleExport.write(demo.snapshot(), to: dryFile)
        let dryDemo = try InstrumentSample.load(url: dryFile).buffer
        let dryPeak = (0..<Int(dryDemo.frameLength)).reduce(Float(0)) { max($0, abs(dryDemo.floatChannelData![0][$1])) }
        precondition(dryPeak > 1, "Demo must demonstrate actual peak reduction: \(dryPeak)")
        demo.limiter.enabled = true
        if CommandLine.arguments.contains("--playback") {
            demo.play(); try await Task.sleep(nanoseconds: 200_000_000)
            precondition(demo.playing && demo.error == nil)
            demo.limiter.ceilingDB = -3; demo.limiter.releaseMS = 40
            try await Task.sleep(nanoseconds: 200_000_000)
            precondition(demo.level > -59)
            demo.pause(); precondition(!demo.playing)
            demo.play(); try await Task.sleep(nanoseconds: 100_000_000)
            demo.stop(); precondition(!demo.playing && demo.level == -60 && demo.parts.allSatisfy { $0.voices == 0 })
        }
        print("PASS: master limiter mono/stereo overloaded peaks, ceilings/releases, bypass, mix/effect tails, v11/legacy, atomic failure, history/AI, demo WAV reload")
    }
}
