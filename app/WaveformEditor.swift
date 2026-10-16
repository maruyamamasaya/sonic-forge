import Foundation

/// End is exclusive, matching audio file frame counts.
struct AudioSelection: Equatable {
    let startFrame: Int64
    let endFrame: Int64
    var frameCount: Int64 { endFrame - startFrame }
}

/// Navigation is normalized; selection is snapped to the source sample grid.
struct WaveformEditor {
    let frameCount: Int64
    let sampleRate: Double
    private(set) var selection: AudioSelection?
    private(set) var visibleRange: Range<Double> = 0..<1
    var zoom: Double { 1 / visibleRange.count }
    var duration: Double { Double(frameCount) / sampleRate }
    var selectionRange: Range<Double>? {
        selection.map { Double($0.startFrame) / Double(frameCount)..<Double($0.endFrame) / Double(frameCount) }
    }
    var selectionStart: Double { Double(selection?.startFrame ?? 0) / sampleRate }
    var selectionEnd: Double { Double(selection?.endFrame ?? 0) / sampleRate }

    mutating func select(from a: Double, to b: Double) {
        guard a.isFinite, b.isFinite else { return }
        let first = Int64((max(0, min(1, min(a, b))) * Double(frameCount)).rounded())
        let last = Int64((max(0, min(1, max(a, b))) * Double(frameCount)).rounded())
        selection = last > first ? AudioSelection(startFrame: first, endFrame: last) : nil
    }
    mutating func clearSelection() { selection = nil }
    mutating func setZoom(_ value: Double, around center: Double) {
        guard value.isFinite, center.isFinite else { return }
        let width = 1 / max(1, min(32, value))
        let start = max(0, min(1 - width, center - width / 2))
        visibleRange = start..<(start + width)
    }
    mutating func pan(to center: Double) { setZoom(zoom, around: center) }
    mutating func fitSelection() {
        guard let range = selectionRange else { return }
        setZoom(1 / max(range.count * 1.15, 1.0 / 32), around: (range.lowerBound + range.upperBound) / 2)
    }
}

extension Range where Bound == Double {
    var count: Double { upperBound - lowerBound }
}
