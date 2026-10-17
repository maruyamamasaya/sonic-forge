import SwiftUI

struct EnsembleTimelineView: View {
    @ObservedObject var ensemble: EnsembleModel
    var expanded = false
    var selectedPart: UUID? = nil
    var selectedClip: UUID? = nil
    var onSelect: (UUID, UUID) -> Void = { _, _ in }
    private var rowHeight: CGFloat { expanded ? 76 : 30 }
    private let scale = 24.0
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var extent: Double {
        let last = ensemble.parts.flatMap(\.allClips).map { clip in
            EnsembleSections.offset(clip.sectionID, in: ensemble.sections) + (clip.startBeat.isFinite ? max(0, min(256, clip.startBeat)) : 0) + (EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount) ?? 0)
        }.max() ?? 0
        return max(32, ceil(max(last, EnsembleSections.end(ensemble.sections)) / 16) * 16 + 8)
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
                    Text("PART").font(.system(size: 9)).foregroundStyle(.secondary).frame(height: ensemble.sections.isEmpty ? 22 : 42)
                    ForEach(ensemble.parts) { part in
                        Button { onSelect(part.id, part.primaryClipID) } label: {
                            TimelinePartLabel(part: part, expanded: expanded)
                                .frame(width: 116, height: rowHeight, alignment: .leading)
                                .background(selectedPart == part.id ? accent.opacity(0.08) : Color.clear)
                        }.buttonStyle(.plain).accessibilityLabel("Select part \(part.name)")
                    }
                }
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        if !ensemble.sections.isEmpty {
                            ZStack(alignment: .topLeading) {
                                ForEach(ensemble.sections) { section in
                                    Text(section.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                                        .padding(.leading, 4).frame(width: max(1, (section.beats.isFinite ? min(256, max(0, section.beats)) : 0) * scale), height: 18, alignment: .leading)
                                        .background(accent.opacity(0.12)).border(accent.opacity(0.25), width: 0.5)
                                        .offset(x: EnsembleSections.offset(section.id, in: ensemble.sections) * scale)
                                        .accessibilityLabel("Section \(section.name), start \(EnsembleSections.offset(section.id, in: ensemble.sections)), length \(section.beats) beats")
                                }
                            }.frame(width: extent * scale, height: 20, alignment: .topLeading)
                        }
                        ZStack(alignment: .topLeading) {
                            ForEach(0...Int(extent / 4), id: \.self) { index in
                                Text("\(index * 4)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    .offset(x: Double(index * 4) * scale + 3, y: 2)
                            }
                        }.frame(width: extent * scale, height: 22, alignment: .topLeading)
                        ForEach(ensemble.parts) { part in
                            TimelineClipRow(part: part, ensemble: ensemble, extent: extent, scale: scale, rowHeight: rowHeight, expanded: expanded, selectedClip: selectedPart == part.id ? selectedClip : nil, onSelect: onSelect)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if ensemble.positionBeats > 0 {
                            Rectangle().fill(accent).frame(width: 1, height: CGFloat(ensemble.sections.isEmpty ? 22 : 42) + CGFloat(ensemble.parts.count) * rowHeight)
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
    var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(part.name + (part.muted ? " · M" : "")).font(.system(size: 11))
                .foregroundStyle(part.muted ? .secondary : .primary).lineLimit(1).help(part.name)
            if expanded {
                Text(part.instrument?.name ?? "No instrument").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Text(String(format: "%.0f dB · %d/8", part.gainDB, part.voices)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, expanded ? 5 : 0)
    }
}

private struct TimelineClipRow: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let extent: Double
    let scale: Double
    let rowHeight: CGFloat
    let expanded: Bool
    let selectedClip: UUID?
    let onSelect: (UUID, UUID) -> Void
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.025))
            ForEach(0...Int(extent / 4), id: \.self) { index in
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).offset(x: Double(index * 4) * scale)
            }
            ForEach(part.allClips) { clip in
                TimelineClipBar(part: part, ensemble: ensemble, clip: clip, scale: scale, expanded: expanded, selected: selectedClip == clip.id, onSelect: onSelect)
            }
        }.frame(width: extent * scale, height: rowHeight).clipped()
    }
}

private struct TimelineClipBar: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let clip: EnsembleClip
    let scale: Double
    let expanded: Bool
    let selected: Bool
    let onSelect: (UUID, UUID) -> Void
    @GestureState private var translation = 0.0
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var maximum: Double {
        guard let section = ensemble.sections.first(where: { $0.id == clip.sectionID }) else { return 256 }
        return max(0, min(256, section.beats - (EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount) ?? 0)))
    }
    private var start: Double {
        EnsembleSections.offset(clip.sectionID, in: ensemble.sections) + (translation == 0 ? (clip.startBeat.isFinite ? max(0, min(256, clip.startBeat)) : 0) :
            min(maximum, EnsembleTimeline.movedStart(original: clip.startBeat, translation: translation, pixelsPerBeat: scale)))
    }
    var body: some View {
        if let length = EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount) {
            RoundedRectangle(cornerRadius: 3).fill(accent.opacity(part.muted ? 0.12 : selected ? 0.40 : 0.24))
                .overlay { RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(selected ? 1 : part.muted ? 0.25 : 0.65), lineWidth: selected ? 2 : 1) }
                .overlay(alignment: .leading) {
                    if let single = EnsembleTimeline.length(clip.performance), clip.repeatCount > 1 {
                        ForEach(1..<clip.repeatCount, id: \.self) { index in
                            Rectangle().fill(accent.opacity(0.6)).frame(width: 1, height: 20).offset(x: Double(index) * ceil(single) * scale)
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 5) {
                        if expanded { Text(clip.performance.name).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                        Text(String(format: "%.2f → %.2f · ×%d", start, start + length, clip.repeatCount))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(accent).lineLimit(1)
                    }.padding(.horizontal, 7)
                }
                .frame(width: max(2, length * scale), height: expanded ? 58 : 22)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 3)
                    .updating($translation) { value, state, _ in if ensemble.canEdit { state = value.translation.width } }
                    .onEnded { value in
                        onSelect(part.id, clip.id)
                        ensemble.movePart(part.id, to: EnsembleTimeline.movedStart(original: clip.startBeat,
                            translation: value.translation.width, pixelsPerBeat: scale), clip: clip.id)
                    })
                .onTapGesture { onSelect(part.id, clip.id) }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onSelect(part.id, clip.id) }
                .accessibilityLabel("Timeline clip for \(part.name), \(clip.performance.name), \(clip.id)")
                .accessibilityValue(String(format: "Start %.2f, length %.2f, end %.2f beats, repeat %d", start, length, start + length, clip.repeatCount))
                .accessibilityAdjustableAction { direction in
                    ensemble.movePart(part.id, to: min(256, max(0, clip.startBeat + (direction == .increment ? 0.25 : -0.25))), clip: clip.id)
                }
                .help("Drag this clip to move in ¼ beats; the instrument is shared by all clips in the row.")
                .offset(x: start * scale)
        } else {
            Text("Invalid performance").font(.system(size: 10)).foregroundStyle(.orange)
        }
    }
}
