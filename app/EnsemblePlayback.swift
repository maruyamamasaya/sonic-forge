import Foundation

/// Audition-only scheduling. End is exclusive; arrangement/WAV events remain untouched.
@MainActor
enum EnsemblePlayback {
    struct Plan {
        let start: Double
        let end: Double
        let initial: [EnsembleModel.Event]
        let events: [EnsembleModel.Event]
    }
    private struct Held {
        var pressed: [Int: Int] = [:]
        var sustained: [Int: Int] = [:]
        var pedals: Set<Int> = []
        var parser = MIDIByteParser()
        mutating func receive(_ bytes: [UInt8]) {
            for message in parser.consume(bytes) {
                let channel = Int(message.channel), key = channel * 128 + message.note
                switch message.kind {
                case let .on(velocity): pressed[key] = velocity; sustained.removeValue(forKey: key)
                case .off:
                    if let velocity = pressed.removeValue(forKey: key), pedals.contains(channel) { sustained[key] = velocity }
                case let .sustain(down):
                    if down { pedals.insert(channel) }
                    else { pedals.remove(channel); sustained = sustained.filter { $0.key / 128 != channel } }
                case .allOff, .silence:
                    pressed = pressed.filter { $0.key / 128 != channel }; sustained = sustained.filter { $0.key / 128 != channel }
                case .resetControllers:
                    pedals.remove(channel); sustained = sustained.filter { $0.key / 128 != channel }
                }
            }
        }
        var bytes: [UInt8] {
            var result: [UInt8] = pedals.sorted().flatMap { channel -> [UInt8] in [UInt8(0xB0 + channel), 64, 127] }
            for key in Set(pressed.keys).union(sustained.keys).sorted() {
                let channel = UInt8(key / 128), note = UInt8(key % 128)
                result += [0x90 + channel, note, UInt8(pressed[key] ?? sustained[key]!)]
                if pressed[key] == nil { result += [0x80 + channel, note, 0] }
            }
            return result
        }
    }
    static func plan(events: [EnsembleModel.Event], start: Double, end: Double, tempo: Double) throws -> Plan {
        guard start.isFinite, end.isFinite, start >= 0, end > start,
              tempo.isFinite, (40...240).contains(tempo) else {
            throw AudioError.invalid("再生範囲は曲の中で、開始より終了を後に指定してください。")
        }
        let first = start * 60 / tempo, last = end * 60 / tempo
        var states: [UUID: Held] = [:], order: [UUID] = []
        for event in events where event.time < first {
            if states[event.part] == nil { states[event.part] = Held(); order.append(event.part) }
            states[event.part]!.receive(event.bytes)
        }
        let initial = order.compactMap { id -> EnsembleModel.Event? in
            let bytes = states[id]!.bytes
            return bytes.isEmpty ? nil : EnsembleModel.Event(time: 0, part: id, bytes: bytes)
        }
        let scheduled = events.filter { $0.time >= first && $0.time < last }.map {
            EnsembleModel.Event(time: $0.time - first, part: $0.part, bytes: $0.bytes)
        }
        return Plan(start: start, end: end, initial: initial, events: scheduled)
    }
}
