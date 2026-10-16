import Foundation
import UniformTypeIdentifiers

struct MIDIPerformanceEvent: Equatable {
    let time: Double
    let bytes: [UInt8]
}

enum MIDIPerformancePreset: String, CaseIterable, Identifiable {
    case softChords = "Soft chords", arpeggio = "Arpeggio", pedalStudy = "Pedal phrase"
    var id: String { rawValue }
    var events: [MIDIPerformanceEvent] {
        switch self {
        case .softChords:
            var events: [MIDIPerformanceEvent] = []
            for (index, notes) in [[60, 64, 67], [60, 65, 69], [59, 62, 67], [60, 64, 67]].enumerated() {
                let velocity = [45, 75, 105, 60][index]
                events.append(MIDIPerformanceEvent(time: Double(index) * 1.3, bytes: notes.flatMap { [0x90, UInt8($0), UInt8(velocity)] }))
                events.append(MIDIPerformanceEvent(time: Double(index) * 1.3 + 0.9, bytes: notes.flatMap { [0x80, UInt8($0), 0] }))
            }
            return events
        case .arpeggio:
            return [60, 64, 67, 72, 67, 64, 60, 55, 60, 64, 67, 72].enumerated().flatMap { index, note in
                [MIDIPerformanceEvent(time: Double(index) * 0.24, bytes: [0x90, UInt8(note), UInt8(50 + index % 4 * 20)]),
                 MIDIPerformanceEvent(time: Double(index) * 0.24 + 0.18, bytes: [0x80, UInt8(note), 0])]
            }
        case .pedalStudy:
            return [MIDIPerformanceEvent(time: 0, bytes: [0xB0, 64, 127, 0x90, 60, 40]),
                    MIDIPerformanceEvent(time: 0.2, bytes: [0x80, 60, 0]),
                    MIDIPerformanceEvent(time: 0.4, bytes: [0x90, 64, 80]),
                    MIDIPerformanceEvent(time: 0.6, bytes: [0x80, 64, 0]),
                    MIDIPerformanceEvent(time: 0.8, bytes: [0x90, 67, 120]),
                    MIDIPerformanceEvent(time: 1, bytes: [0x80, 67, 0]),
                    MIDIPerformanceEvent(time: 2, bytes: [0xB0, 64, 0])]
        }
    }
}


struct PerformanceNote: Codable, Equatable {
    var beat: Double
    var duration: Double
    var pitch: Int
    var velocity: Int
    var channel: Int = 0
}
struct PerformancePedal: Codable, Equatable {
    var beat: Double
    var down: Bool
    var channel: Int = 0
}

extension UTType {
    static let sonicForgePerformance = UTType(exportedAs: "local.sonicforge.performance", conformingTo: .json)
}

/// Beats are quarter notes; MIDI channels in the file are zero-based.
struct PerformanceDocument: Codable, Equatable {
    var version = 1
    var name: String
    var tempo = 120.0
    var transpose = 0
    var velocityPercent = 100.0
    var notes: [PerformanceNote]
    var pedals: [PerformancePedal]

    static func preset(_ preset: MIDIPerformancePreset) -> Self {
        var parser = MIDIByteParser()
        var pending: [Int: (Double, Int)] = [:]
        var notes: [PerformanceNote] = [], pedals: [PerformancePedal] = []
        for event in preset.events {
            for message in parser.consume(event.bytes) {
                let key = Int(message.channel) * 128 + message.note
                switch message.kind {
                case let .on(velocity): pending[key] = (event.time * 2, velocity)
                case .off:
                    if let (beat, velocity) = pending.removeValue(forKey: key) {
                        notes.append(PerformanceNote(beat: beat, duration: event.time * 2 - beat, pitch: message.note, velocity: velocity, channel: Int(message.channel)))
                    }
                case let .sustain(down): pedals.append(PerformancePedal(beat: event.time * 2, down: down, channel: Int(message.channel)))
                default: break
                }
            }
        }
        return Self(name: preset.rawValue, notes: notes.sorted { $0.beat < $1.beat }, pedals: pedals)
    }

    func events(root: Int? = nil) throws -> [MIDIPerformanceEvent] {
        func invalid(_ detail: String) -> AudioError { .invalid("演奏データが無効です。" + detail) }
        guard version == 1 else { throw invalid("未対応のバージョンです。") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              tempo.isFinite, (40...240).contains(tempo), (-24...24).contains(transpose),
              velocityPercent.isFinite, (25...150).contains(velocityPercent),
              (1...256).contains(notes.count), pedals.count <= 64 else { throw invalid("名前・テンポ・調整値・イベント数を確認してください。") }
        if let root, !(0...127).contains(root) { throw invalid("基準音が無効です。") }
        // Order coincident events: pedal-up, note-off, pedal-down, note-on.
        var timeline: [(beat: Double, priority: Int, bytes: [UInt8])] = []
        for note in notes {
            guard note.beat.isFinite, note.duration.isFinite, note.beat >= 0, note.duration > 0,
                  note.beat + note.duration <= 256, (0...127).contains(note.pitch),
                  (1...127).contains(note.velocity), (0...15).contains(note.channel) else { throw invalid("音符の位置・長さ・音程・強さを確認してください。") }
            let pitch = note.pitch + transpose
            guard (0...127).contains(pitch) else { throw invalid("移調後の音程がMIDIの範囲外です。") }
            if let root, abs(pitch - root) > 24 { throw invalid("移調後の音程は楽器の基準音±24半音以内にしてください。") }
            let velocity = min(127, max(1, Int((Double(note.velocity) * velocityPercent / 100).rounded())))
            timeline.append((note.beat, 3, [0x90 | UInt8(note.channel), UInt8(pitch), UInt8(velocity)]))
            timeline.append((note.beat + note.duration, 1, [0x80 | UInt8(note.channel), UInt8(pitch), 0]))
        }
        for pedal in pedals {
            guard pedal.beat.isFinite, (0...256).contains(pedal.beat), (0...15).contains(pedal.channel) else { throw invalid("ペダルの位置・チャンネルを確認してください。") }
            timeline.append((pedal.beat, pedal.down ? 2 : 0, [0xB0 | UInt8(pedal.channel), 64, pedal.down ? 127 : 0]))
        }
        let sorted = timeline.enumerated().sorted {
            if $0.element.beat != $1.element.beat { return $0.element.beat < $1.element.beat }
            if $0.element.priority != $1.element.priority { return $0.element.priority < $1.element.priority }
            return $0.offset < $1.offset
        }.map(\.element)
        var pressed: Set<Int> = [], sustained: Set<Int> = [], down: Set<Int> = []
        for event in sorted {
            let channel = Int(event.bytes[0] & 15), pitch = Int(event.bytes[1])
            let key = channel * 128 + pitch
            switch event.priority {
            case 0:
                down.remove(channel); sustained = sustained.filter { $0 / 128 != channel }
            case 1:
                pressed.remove(key)
                if down.contains(channel) { sustained.insert(key) }
            case 2: down.insert(channel)
            default:
                guard !pressed.contains(key) else { throw invalid("同じチャンネル・音程の音符が重なっています。") }
                sustained.remove(key); pressed.insert(key)
            }
            guard Set(pressed.union(sustained).map { $0 % 128 }).count <= 8 else { throw invalid("ペダル保持を含めて最大8音です。") }
        }
        guard down.isEmpty else { throw invalid("最後にペダルを解除してください。") }
        return sorted.map { MIDIPerformanceEvent(time: $0.beat * 60 / tempo, bytes: $0.bytes) }
    }
    static func load(_ url: URL) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && size <= 1_048_576 else { throw AudioError.invalid("演奏ファイルは1 MB以下にしてください。") }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        _ = try value.events()
        return value
    }
    func save(to url: URL) throws {
        guard url.pathExtension.lowercased() == "sfperformance" else { throw AudioError.invalid("演奏は.sfperformance形式で保存してください。") }
        _ = try events()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
