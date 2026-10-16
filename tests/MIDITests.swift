import Foundation
import CoreMIDI
import AVFoundation

@MainActor
enum MIDITests {
    static func parser() {
        var parser = MIDIByteParser()
        precondition(parser.consume([0x90, 60]).isEmpty)
        precondition(parser.consume([100, 64, 0, 0xF8, 0x81, 67, 0]) == [
            MIDIMessage(channel: 0, note: 60, kind: .on(100)),
            MIDIMessage(channel: 0, note: 64, kind: .off),
            MIDIMessage(channel: 1, note: 67, kind: .off)])
        precondition(parser.consume([0xF0, 1, 2, 0xF7, 60, 1]).isEmpty)
        precondition(parser.consume([0xB3, 123, 0, 120, 0]) == [MIDIMessage(channel: 3, note: 0, kind: .allOff), MIDIMessage(channel: 3, note: 0, kind: .silence)])
        precondition(parser.consume([0xC0, 4, 5, 0xE0, 1, 2, 0x90, 1]).isEmpty)
        precondition(parser.consume([90]) == [MIDIMessage(channel: 0, note: 1, kind: .on(90))])
        precondition(parser.consume([0xB2, 64, 63, 64, 64, 64, 127, 64, 0, 121, 0]) == [
            MIDIMessage(channel: 2, note: 0, kind: .sustain(false)), MIDIMessage(channel: 2, note: 0, kind: .sustain(true)),
            MIDIMessage(channel: 2, note: 0, kind: .sustain(true)), MIDIMessage(channel: 2, note: 0, kind: .sustain(false)),
            MIDIMessage(channel: 2, note: 0, kind: .resetControllers)])
        for preset in MIDIPerformancePreset.allCases {
            let events = preset.events
            precondition(!events.isEmpty && zip(events, events.dropFirst()).allSatisfy { $0.time <= $1.time })
            var parser = MIDIByteParser()
            var held: Set<Int> = [], pedal = false
            for event in events {
                for message in parser.consume(event.bytes) {
                    switch message.kind {
                    case .on: held.insert(message.note)
                    case .off: held.remove(message.note)
                    case let .sustain(down): pedal = down
                    default: break
                    }
                }
            }
            precondition(held.isEmpty && !pedal)
        }
        print("PASS: CC64 thresholds and preset notes/pedal balanced")
        print("PASS: MIDI running status, split messages, velocity-zero off, channel panic and ignored system messages")
    }
    static func expression() async throws {
        let engine = AVAudioEngine()
        let sampler = SampleInstrument(engine: engine)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1000)!
        pcm.frameLength = 1000
        for channel in 0..<2 { for i in 0..<1000 { pcm.floatChannelData![channel][i] = 1 } }
        sampler.install(InstrumentSample(buffer: pcm, name: "constant", selection: AudioSelection(startFrame: 0, endFrame: 1000)))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        var levels: [Float] = []
        for velocity in [32, 64, 127] {
            sampler.stop()
            try sampler.play(note: 60, root: 60, envelope: .legacy, loop: SampleLoop(enabled: true, endFrame: 1000), velocity: velocity)
            for _ in 0..<10 { let status = try engine.renderOffline(512, to: buffer); precondition(status == .success) }
            levels.append(buffer.floatChannelData![0][400])
        }
        precondition(abs(levels[0] / levels[2] - 32.0 / 127) < 0.001)
        precondition(abs(levels[1] / levels[2] - 64.0 / 127) < 0.001)
        sampler.stop()
        for (note, velocity) in [(60, 32), (64, 64), (67, 127)] {
            try sampler.play(note: note, root: 60, envelope: .legacy, loop: SampleLoop(enabled: true, endFrame: 1000), velocity: velocity)
        }
        for _ in 0..<10 { _ = try engine.renderOffline(512, to: buffer) }
        precondition(abs(buffer.floatChannelData![0][400] / levels[2] - 223.0 / 127) < 0.005)
        sampler.noteOff(64)
        for _ in 0..<10 { _ = try engine.renderOffline(512, to: buffer) }
        precondition(abs(buffer.floatChannelData![0][400] / levels[2] - 159.0 / 127) < 0.005)
        sampler.shutdown(); engine.disableManualRenderingMode()

        let model = PlayerModel()
        defer { model.cleanup() }
        await model.loadDemo()
        model.setLoop(SampleLoop(enabled: true, startFrame: 4800, endFrame: 9600, crossfadeFrames: 480))
        model.setEnvelope(ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.05))
        let midi = model.midi
        midi.createTestInput()
        func settle() async throws { try await Task.sleep(nanoseconds: 150_000_000); model.refreshPlaybackState() }
        midi.sendTest([0xB0, 64, 127, 0x90, 60, 32, 0x80, 60, 0])
        try await settle()
        precondition(model.sustainChannels == [0] && model.activeNotes == [60])
        midi.sendTest([0x90, 60, 110, 0x90, 60, 0]) // reattack then velocity-zero off, still sustained
        try await settle()
        precondition(model.activeNotes == [60] && model.soundingVoices == 1)
        model.playNote(64)
        midi.sendTest([0x91, 67, 90, 0x81, 67, 0]) // channel 2 is not sustained
        try await settle()
        precondition(model.activeNotes == [60, 64])
        midi.sendTest([0xB0, 64, 0])
        try await settle()
        precondition(model.activeNotes == [64] && model.sustainChannels.isEmpty)
        model.stopInstrument()
        midi.sendTest([0xB0, 64, 127, 0x90, 60, 80, 64, 80, 0xB0, 123, 0])
        try await settle()
        precondition(model.activeNotes == [60, 64]) // CC123 respects pedal
        midi.sendTest([0xB0, 121, 0])
        try await settle()
        precondition(model.activeNotes.isEmpty && model.sustainChannels.isEmpty)
        midi.sendTest([0xB0, 64, 127, 0x90, 60, 80, 0x80, 60, 0])
        try await settle()
        midi.select(0)
        precondition(model.activeNotes.isEmpty && model.sustainChannels.isEmpty)
        midi.createTestInput()
        midi.sendTest([0xB0, 64, 127, 0xB1, 64, 127, 0x90, 60, 80, 0x80, 60, 0, 0x91, 67, 80, 0x81, 67, 0])
        try await settle()
        precondition(model.sustainChannels == [0, 1] && model.activeNotes == [60, 67])
        midi.sendTest([0xB0, 64, 0])
        try await settle()
        precondition(model.activeNotes == [67] && model.sustainChannels == [1])
        model.suspendMIDI(true)
        precondition(model.activeNotes.isEmpty && model.sustainChannels.isEmpty)
        model.suspendMIDI(false)
        midi.performancePreset = .pedalStudy
        midi.playPerformance()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        model.refreshPlaybackState()
        precondition(model.sustainChannels == [0] && model.activeNotes == [60, 64, 67])
        midi.stopPerformance()
        try await settle()
        precondition(!midi.performing && model.activeNotes.isEmpty && model.sustainChannels.isEmpty)
        midi.playPerformance()
        try await Task.sleep(nanoseconds: 2_400_000_000)
        model.refreshPlaybackState()
        precondition(!midi.performing && model.activeNotes.isEmpty && model.sustainChannels.isEmpty)
        print("PASS: actual graph velocity ratios, virtual MIDI sustain/retrigger/channels/reset/disconnect, automatic pedal phrase and cancellation")
    }
    static func integration() async throws {
        let model = PlayerModel()
        defer { model.cleanup() }
        await model.loadDemo()
        model.setLoop(SampleLoop(enabled: true, startFrame: 4800, endFrame: 9600, crossfadeFrames: 480))
        model.setEnvelope(ADSRParameters(attack: 0.01, decay: 0.02, sustain: 0.7, release: 0.05))
        let midi = model.midi
        midi.createTestInput()
        precondition(midi.error == nil && midi.selected != 0 && midi.selected == midi.testSource, midi.error ?? "No virtual MIDI")
        func settle() async throws { try await Task.sleep(nanoseconds: 150_000_000); model.refreshPlaybackState() }
        midi.sendTest([0x90, 57, 100, 61, 100, 64, 100])
        try await settle()
        precondition(model.activeNotes == [57, 61, 64] && model.soundingVoices == 3)
        try await Task.sleep(nanoseconds: 300_000_000)
        model.refreshPlaybackState()
        precondition(model.activeNotes == [57, 61, 64] && model.levels[0] > -60)
        midi.sendTest([0x90, 61, 0])
        try await settle()
        precondition(model.activeNotes == [57, 64] && model.soundingVoices == 2)
        // Screen ownership and different MIDI channels must be independent.
        model.playNote(57)
        midi.sendTest([0x91, 57, 100, 0x80, 57, 0, 0xB0, 123, 0])
        try await settle()
        precondition(model.activeNotes == [57])
        model.releaseNote(57)
        precondition(model.activeNotes == [57])
        midi.sendTest([0x81, 57, 0])
        try await settle()
        precondition(model.activeNotes.isEmpty && model.levels == [-60, -60])
        // Physical MIDI notes can extend beyond the on-screen C3–C5 keyboard.
        midi.sendTest([0x90, 40, 100])
        try await settle()
        precondition(model.activeNotes == [40])
        midi.sendTest([0xB0, 120, 0])
        try await settle()
        precondition(model.activeNotes.isEmpty && model.soundingVoices == 0)
        midi.sendTest([0x90, 60, 100])
        try await settle()
        model.playNote(57)
        midi.sendTest([0x90, 65, 100]) // queued before disconnect: must not arrive afterward
        midi.select(0)
        try await settle()
        precondition(model.activeNotes == [57] && model.soundingVoices == 1)
        model.releaseNote(57)
        try await settle()
        midi.sendTest([0x90, 64, 100])
        try await settle()
        precondition(model.activeNotes.isEmpty)
        midi.select(midi.testSource)
        midi.sendTest([0x90, 64, 100])
        model.suspendMIDI(true)
        try await settle()
        precondition(model.activeNotes.isEmpty)
        model.suspendMIDI(false)
        midi.sendTest([0x90, 64, 100])
        try await settle()
        precondition(model.activeNotes == [64])
        // All Sound Off must also kill already-released MIDI tails.
        model.setEnvelope(ADSRParameters(release: 1))
        midi.sendTest([0x90, 60, 100, 0x80, 60, 0])
        try await settle()
        precondition(model.soundingVoices > 0)
        midi.sendTest([0xB0, 120, 0])
        try await settle()
        precondition(model.soundingVoices == 0)
        midi.sendTest([0x90, 60, 100, 0x80, 60, 0])
        try await settle()
        midi.sendTest([0x91, 60, 100, 0x81, 60, 0])
        try await settle()
        midi.sendTest([0xB0, 120, 0])
        try await settle()
        precondition(model.soundingVoices == 1) // old channel must not kill a new voice's tail
        midi.sendTest([0xB1, 120, 0])
        try await settle()
        precondition(model.soundingVoices == 0)
        // A second real virtual endpoint exercises source removal and stale delivery.
        let second = MIDIInput()
        second.createTestInput()
        defer { second.close() }
        midi.refresh(); midi.select(second.testSource)
        second.sendTest([0x90, 67, 100])
        try await settle()
        precondition(model.activeNotes == [67])
        second.close()
        try await settle()
        midi.refresh()
        precondition(midi.selected == 0 && model.activeNotes.isEmpty && model.soundingVoices == 0)
        print("PASS: virtual CoreMIDI routing, polyphony/ADSR/loop, channels, velocity-zero, panic, source selection/removal and suspended input")
    }
}
