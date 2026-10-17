import SwiftUI

struct EnsembleTimelineView: View {
    @ObservedObject var ensemble: EnsembleModel
    private let scale = 24.0
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var extent: Double {
        let last = ensemble.parts.map { part in
            (part.startBeat.isFinite ? max(0, min(256, part.startBeat)) : 0) + (EnsembleTimeline.repeatedLength(part.performance, count: part.repeatCount) ?? 0)
        }.max() ?? 0
        return max(32, ceil(last / 16) * 16 + 8)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ARRANGEMENT").font(.system(size: 10, weight: .medium)).tracking(1.5)
                Spacer()
                Text("Beats · Drag to move · Snap ¼ · Scroll horizontally")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PART").font(.system(size: 9)).foregroundStyle(.secondary).frame(height: 22)
                    ForEach(ensemble.parts) { part in
                        TimelinePartLabel(part: part).frame(width: 116, height: 30, alignment: .leading)
                    }
                }
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            ForEach(0...Int(extent / 4), id: \.self) { index in
                                Text("\(index * 4)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    .offset(x: Double(index * 4) * scale + 3, y: 2)
                            }
                        }.frame(width: extent * scale, height: 22, alignment: .topLeading)
                        ForEach(ensemble.parts) { part in
                            TimelineClipRow(part: part, ensemble: ensemble, extent: extent, scale: scale)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if ensemble.positionBeats > 0 {
                            Rectangle().fill(accent).frame(width: 1, height: CGFloat(22 + ensemble.parts.count * 30))
                                .offset(x: ensemble.positionBeats * scale).allowsHitTesting(false)
                        }
                    }
                }
            }
            Text("Clip length includes rests and pedal events; Release tails continue beyond the clip.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(12).background(Color.black.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)) }
    }
}

private struct TimelinePartLabel: View {
    @ObservedObject var part: EnsemblePart
    var body: some View {
        Text(part.name + (part.muted ? " · M" : "")).font(.system(size: 10))
            .foregroundStyle(part.muted ? .secondary : .primary).lineLimit(1).help(part.name)
    }
}

private struct TimelineClipRow: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let extent: Double
    let scale: Double
    @GestureState private var translation = 0.0
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var start: Double {
        translation == 0 ? (part.startBeat.isFinite ? max(0, min(256, part.startBeat)) : 0) :
            EnsembleTimeline.movedStart(original: part.startBeat, translation: translation, pixelsPerBeat: scale)
    }
    var body: some View {
        let length = EnsembleTimeline.repeatedLength(part.performance, count: part.repeatCount)
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.025))
            ForEach(0...Int(extent / 4), id: \.self) { index in
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).offset(x: Double(index * 4) * scale)
            }
            if let length {
                RoundedRectangle(cornerRadius: 3).fill(accent.opacity(part.muted ? 0.12 : 0.24))
                    .overlay { RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(part.muted ? 0.25 : 0.65)) }
                    .overlay(alignment: .leading) {
                        if let single = EnsembleTimeline.length(part.performance), part.repeatCount > 1 {
                            ForEach(1..<part.repeatCount, id: \.self) { index in
                                Rectangle().fill(accent.opacity(0.6)).frame(width: 1, height: 20)
                                    .offset(x: Double(index) * ceil(single) * scale)
                            }
                        }
                    }
                    .overlay(alignment: .leading) {
                        Text(String(format: "%.2f → %.2f · ×%d", start, start + length, part.repeatCount))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(accent)
                            .padding(.horizontal, 7).lineLimit(1)
                    }
                    .frame(width: max(2, length * scale), height: 22).offset(x: start * scale)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3)
                        .updating($translation) { value, state, _ in
                            if ensemble.canEdit { state = value.translation.width }
                        }
                        .onEnded { value in
                            ensemble.movePart(part.id, to: EnsembleTimeline.movedStart(original: part.startBeat,
                                translation: value.translation.width, pixelsPerBeat: scale))
                        })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Timeline clip for \(part.name)")
                    .accessibilityValue(String(format: "Start %.2f, length %.2f, end %.2f beats, repeat %d", part.startBeat, length, part.startBeat + length, part.repeatCount))
                    .accessibilityAdjustableAction { direction in
                        guard ensemble.canEdit else { return }
                        ensemble.movePart(part.id, to: min(256, max(0, part.startBeat + (direction == .increment ? 0.25 : -0.25))))
                    }
                    .help("Drag to move in ¼ beats. Use START for an exact value.")
            } else {
                Text("Invalid performance").font(.system(size: 10)).foregroundStyle(.orange).padding(.leading, 4)
            }
        }.frame(width: extent * scale, height: 30).clipped()
    }
}
