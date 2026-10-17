import Foundation

/// Display key-down durations, not sustain-pedal or audio Release tails.
struct PerformanceNoteLayout {
    struct Note: Equatable {
        let beat: Double
        let duration: Double
        let pitch: Int
        let velocity: Int
    }
    let notes: [Note]
    let length: Double
    let cycle: Double
    let pitchRange: ClosedRange<Int>
    static func make(_ performance: PerformanceDocument, repeatCount: Int, root: Int? = nil) throws -> Self {
        guard (1...16).contains(repeatCount) else { throw AudioError.invalid("繰り返し回数が無効です。") }
        _ = try performance.events(root: root)
        var beats = performance; beats.tempo = 60
        let events = try beats.events(root: root)
        let single = events.last!.time, cycle = ceil(single)
        let notes = (0..<repeatCount).flatMap { pass in
            performance.notes.map { note in
                Note(beat: note.beat + Double(pass) * cycle, duration: note.duration,
                     pitch: note.pitch + performance.transpose,
                     velocity: min(127, max(1, Int((Double(note.velocity) * performance.velocityPercent / 100).rounded()))))
            }
        }
        let low = notes.map(\.pitch).min()!, high = notes.map(\.pitch).max()!
        let center = root ?? (low + high) / 2
        let lower = max(0, min(low - 2, center - 12)), upper = min(127, max(high + 2, center + 12))
        return Self(notes: notes, length: Double(repeatCount - 1) * cycle + single, cycle: cycle, pitchRange: lower...upper)
    }
}
