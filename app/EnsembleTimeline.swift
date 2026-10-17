import Foundation

/// Timeline clips cover performance events (including rests/pedal), not audio Release tails.
enum EnsembleTimeline {
    static func length(_ performance: PerformanceDocument) -> Double? {
        var copy = performance; copy.tempo = 60
        return try? copy.events().last?.time
    }
    /// Repeat at whole-beat boundaries; the last pass keeps its original event end.
    static func repeatedLength(_ performance: PerformanceDocument, count: Int) -> Double? {
        guard (1...16).contains(count), let length = length(performance) else { return nil }
        return Double(count - 1) * ceil(length) + length
    }
    static func events(_ performance: PerformanceDocument, root: Int, tempo: Double,
                       startBeat: Double, count: Int) throws -> [MIDIPerformanceEvent] {
        guard (1...16).contains(count), startBeat.isFinite, (0...2304).contains(startBeat),
              tempo.isFinite, (40...240).contains(tempo) else { throw AudioError.invalid("開始位置・繰り返し回数・テンポを確認してください。") }
        _ = try performance.events(root: root)
        var beats = performance; beats.tempo = 60
        let source = try beats.events(root: root)
        let cycle = ceil(source.last!.time)
        return (0..<count).flatMap { pass in
            source.map { MIDIPerformanceEvent(time: ($0.time + startBeat + Double(pass) * cycle) * 60 / tempo, bytes: $0.bytes) }
        }
    }
    static func movedStart(original: Double, translation: Double, pixelsPerBeat: Double) -> Double {
        guard original.isFinite, translation.isFinite, pixelsPerBeat.isFinite, pixelsPerBeat > 0 else { return 0 }
        return min(256, max(0, ((original + translation / pixelsPerBeat) * 4).rounded() / 4))
    }
}
