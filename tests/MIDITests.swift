import Foundation
import CoreMIDI

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
        print("PASS: MIDI running status, split messages, velocity-zero off, channel panic and ignored system messages")
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
