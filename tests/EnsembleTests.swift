import Foundation
import AVFoundation

enum EnsembleTests {
    @MainActor static func run() async throws {
        let ensemble = EnsembleModel()
        do { _ = try ensemble.timeline(); fatalError("Empty ensemble accepted") } catch {}
        await ensemble.addDemos()
        precondition(ensemble.parts.count == 2 && ensemble.error == nil)
        let first = ensemble.parts[0], second = ensemble.parts[1]
        let tempos = ensemble.parts.map { $0.performance.tempo }
        ensemble.tempo = 120
        let events = try ensemble.timeline()
        precondition(events.count == 88 && events.filter { $0.time == 0 }.count == 4)
        precondition(Set(events.map(\.part)).count == 2)
        precondition(ensemble.parts.map { $0.performance.tempo } == tempos)
        precondition(abs(events.last!.time - 15.87 / 2) < 0.000001)
        ensemble.tempo = 60
        let slower = try ensemble.timeline()
        precondition(abs(slower.last!.time - events.last!.time * 2) < 0.000001)
        ensemble.tempo = .nan
        do { _ = try ensemble.timeline(); fatalError("NaN tempo accepted") } catch {}
        ensemble.tempo = 120
        let original = first.performance
        var invalid = original; invalid.notes[0].pitch = 127
        ensemble.setPerformance(invalid, part: first.id)
        precondition(first.performance == original && ensemble.error != nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-EnsembleTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("part.sfinstrument")
        let instrument = first.instrument!
        try InstrumentDocument.save(sample: instrument.sample, rootNote: instrument.root, envelope: instrument.envelope, loop: instrument.loop, to: file)
        await ensemble.loadInstrument(file, part: second.id)
        precondition(second.instrumentURL == file && second.instrument!.loop == instrument.loop && second.instrument!.envelope == instrument.envelope)
        let bad = directory.appendingPathComponent("broken.sfinstrument")
        try Data("broken".utf8).write(to: bad)
        await ensemble.loadInstrument(bad, part: second.id)
        precondition(second.instrumentURL == file && ensemble.error != nil)
        let performanceFile = directory.appendingPathComponent("part.sfperformance")
        try original.save(to: performanceFile)
        ensemble.setPerformance(try PerformanceDocument.load(performanceFile), part: second.id)
        precondition(second.performance == original)
        precondition(ensemble.addPart() != nil && ensemble.addPart() != nil && ensemble.addPart() == nil)
        do { _ = try ensemble.timeline(); fatalError("Incomplete part accepted") } catch {}
        ensemble.play()
        precondition(!ensemble.playing && ensemble.error != nil && first.voices == 0)
        ensemble.remove(ensemble.parts.last!.id)
        ensemble.remove(ensemble.parts.last!.id)
        precondition(ensemble.parts.count == 2)
        first.gainDB = .infinity
        do { _ = try ensemble.timeline(); fatalError("Invalid gain accepted") } catch {}
        first.gainDB = 0
        ensemble.stop()
        print("PASS: ensemble shared tempo, independent assignments, four-part limit, invalid/missing data rejection and failed replacement preservation")
    }
    @MainActor static func integration() async throws {
        // Two independent voices on one output graph, at different sample rates.
        func sample(rate: Double, frequency: Double) -> InstrumentSample {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate))!
            buffer.frameLength = buffer.frameCapacity
            for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * frequency / rate) * 0.6) }
            return InstrumentSample(buffer: buffer, name: "tone", selection: AudioSelection(startFrame: 0, endFrame: Int64(buffer.frameLength)))
        }
        let engine = AVAudioEngine()
        var voices: [EnsembleVoice] = []
        for (index, tone) in [sample(rate: 44100, frequency: 440), sample(rate: 48000, frequency: 660)].enumerated() {
            let mixer = AVAudioMixerNode(); engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
            let instrument = EnsembleInstrument(sample: tone, root: 60, envelope: ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.05),
                loop: SampleLoop(enabled: true, endFrame: Int64(tone.buffer.frameLength)), name: "Tone \(index)")
            let voice = EnsembleVoice(instrument: instrument, engine: engine, mixer: mixer)
            voice.sampler.gain = 1; voices.append(voice)
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try voices[0].receive([0xB0, 64, 127, 0x90, 60, 127, 0x80, 60, 0])
        try voices[1].receive([0x90, 60, 127])
        precondition(voices[0].pedalChannels == [0] && voices[0].heldNotes == [60] && voices[1].heldNotes == [60])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        func render() throws -> [Float] {
            var data: [Float] = []
            for _ in 0..<40 {
                let status = try engine.renderOffline(512, to: buffer)
                precondition(status == .success)
                data += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            }
            return data
        }
        func amplitude(_ data: [Float], frequency: Double) -> Double {
            let range = 6000..<data.count
            var real = 0.0, imaginary = 0.0
            for index in range {
                let phase = 2 * Double.pi * frequency * Double(index) / 44100
                real += Double(data[index]) * cos(phase); imaginary += Double(data[index]) * sin(phase)
            }
            return hypot(real, imaginary) * 2 / Double(range.count)
        }
        let both = try render()
        precondition(amplitude(both, frequency: 440) > 0.02 && amplitude(both, frequency: 660) > 0.02)
        try voices[0].receive([0xB0, 64, 0])
        let one = try render()
        precondition(amplitude(one, frequency: 440) < 0.001 && amplitude(one, frequency: 660) > 0.02)
        precondition(voices[1].heldNotes == [60])
        voices.forEach { $0.stop() }; engine.stop()
        print("PASS: shared graph simultaneously renders 440/660 Hz at mixed sample rates; independent same-pitch sustain and Release")
        let ensemble = EnsembleModel()
        await ensemble.addDemos(); ensemble.tempo = 240; ensemble.masterDB = -6
        let first = ensemble.parts[0], second = ensemble.parts[1]
        ensemble.play()
        try await Task.sleep(nanoseconds: 180_000_000)
        precondition(ensemble.playing && first.voices >= 3 && second.voices > 0)
        precondition(first.level > -60 && second.level > -60 && ensemble.level > -60)
        precondition(ensemble.heldNotes(part: first.id).contains(57))
        first.muted = true
        try await Task.sleep(nanoseconds: 250_000_000)
        precondition(first.level <= -59 && second.level > -60 && ensemble.playing)
        first.muted = false
        ensemble.stop()
        precondition(!ensemble.playing && ensemble.parts.allSatisfy { $0.voices == 0 && $0.level == -60 })
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(ensemble.heldNotes(part: first.id).isEmpty)
        // Last event releases each part, then the shared engine ends naturally.
        ensemble.play()
        try await Task.sleep(nanoseconds: 4_800_000_000)
        precondition(!ensemble.playing && ensemble.parts.allSatisfy { $0.voices == 0 } && ensemble.positionBeats > 15)
        // All four dedicated mixer buses remain audible.
        await ensemble.addDemos()
        precondition(ensemble.parts.count == 4)
        ensemble.play()
        try await Task.sleep(nanoseconds: 180_000_000)
        precondition(ensemble.playing && ensemble.parts.allSatisfy { $0.voices > 0 && $0.level > -60 })
        ensemble.stop()
        // Invalid one-part data blocks the entire transport before any sound starts.
        ensemble.remove(ensemble.parts.last!.id)
        ensemble.addPart()
        ensemble.play()
        precondition(!ensemble.playing && ensemble.error != nil)
        print("PASS: demo duo/four-part output, live mute, stop/restart, natural Release completion and atomic validation")
    }
}
