import Foundation

/// Timeline clips cover performance events (including rests/pedal), not audio Release tails.
enum EnsembleTimeline {
    static func length(_ performance: PerformanceDocument) -> Double? {
        var copy = performance; copy.tempo = 60
        return try? copy.events().last?.time
    }
    static func movedStart(original: Double, translation: Double, pixelsPerBeat: Double) -> Double {
        guard original.isFinite, translation.isFinite, pixelsPerBeat.isFinite, pixelsPerBeat > 0 else { return 0 }
        return min(256, max(0, ((original + translation / pixelsPerBeat) * 4).rounded() / 4))
    }
}
