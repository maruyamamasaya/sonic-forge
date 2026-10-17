import SwiftUI

struct PerformanceNoteView: View, Equatable {
    let performance: PerformanceDocument
    var repeatCount = 1
    var root: Int? = nil
    var detail = false
    var selected = false
    var body: some View {
        if let layout = try? PerformanceNoteLayout.make(performance, repeatCount: repeatCount, root: root) {
            HStack(spacing: 0) {
                if detail {
                    VStack(alignment: .trailing) {
                        Text(NotePitch.name(layout.pitchRange.upperBound))
                        Spacer()
                        Text(NotePitch.name((layout.pitchRange.lowerBound + layout.pitchRange.upperBound) / 2))
                        Spacer()
                        Text(NotePitch.name(layout.pitchRange.lowerBound))
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(8).frame(width: 52)
                        .background(Color.white.opacity(0.035))
                }
                Canvas { context, size in
                    let range = Double(layout.pitchRange.upperBound - layout.pitchRange.lowerBound + 1)
                    let noteHeight = size.height / range
                    if detail {
                        var grid = Path()
                        for index in 0...Int(range) {
                            let y = Double(index) * noteHeight
                            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        // Bound grid work even for a long, repeated performance.
                        let step = max(1, ceil(layout.length / 64))
                        for beat in stride(from: 0.0, through: layout.length, by: step) {
                            let x = beat / max(0.001, layout.length) * size.width
                            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        context.stroke(grid, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
                    }
                    for note in layout.notes {
                        let x = note.beat / layout.length * size.width
                        let y = Double(layout.pitchRange.upperBound - note.pitch) * noteHeight
                        let rect = CGRect(x: x, y: y, width: max(1, note.duration / layout.length * size.width), height: max(detail ? 1 : 1.8, noteHeight * (detail ? 0.75 : 0.65)))
                        context.fill(Path(roundedRect: rect, cornerRadius: detail ? 1.5 : 0.5), with: .color(Color(red: selected ? 0.94 : 0.76, green: selected ? 0.83 : 0.79, blue: selected ? 0.58 : 0.58).opacity(0.42 + Double(note.velocity) / 220)))
                    }
                }.clipped()
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(detail ? "Selected clip note detail" : "Performance note preview")
                .accessibilityValue("\(layout.notes.count) notes, \(layout.length.formatted()) beats, \(NotePitch.name(layout.pitchRange.lowerBound)) to \(NotePitch.name(layout.pitchRange.upperBound))")
                .help("Key-down durations; pedal sustain and Release tails are not shown as longer notes.")
        } else {
            Text("Invalid performance").font(.system(size: 11)).foregroundStyle(.orange)
        }
    }
}

struct SelectedClipNotes: View {
    @ObservedObject var part: EnsemblePart
    let clipID: UUID
    private var clip: EnsembleClip { part.allClips.first { $0.id == clipID } ?? part.allClips[0] }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NOTE DETAIL").tracking(1.3)
                Text(clip.performance.name).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("×\(clip.repeatCount) · Read only").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 12).frame(height: 30)
            Divider()
            PerformanceNoteView(performance: clip.performance, repeatCount: clip.repeatCount, root: part.instrument?.root, detail: true, selected: true).equatable()
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.12))
            HStack {
                Text("Pitch ↑ · Time →")
                Spacer()
                Text("\(clip.performance.notes.count * clip.repeatCount) notes · Key-down lengths")
            }.font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 22)
        }.background(Color(red: 0.105, green: 0.13, blue: 0.095))
            .overlay { Rectangle().stroke(.black.opacity(0.4), lineWidth: 1).allowsHitTesting(false) }
    }
}
