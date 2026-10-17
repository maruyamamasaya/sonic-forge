import SwiftUI

/// One cycle is edited; clip repeats are generated from this same source document.
struct SelectedClipNotes: View {
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var part: EnsemblePart
    let clipID: UUID
    @State private var selected: Int?
    @State private var pitch = "60"
    @State private var beat = "0"
    @State private var duration = "1"
    @State private var velocity = "90"
    private var clip: EnsembleClip? { part.allClips.first { $0.id == clipID } }
    private var accent: Color { Color(red: 0.90, green: 0.78, blue: 0.51) }
    private func select(_ index: Int) {
        guard let clip, clip.performance.notes.indices.contains(index) else { return }
        selected = index
        let note = clip.performance.notes[index]
        pitch = String(note.pitch + clip.performance.transpose); beat = String(note.beat)
        duration = String(note.duration); velocity = String(note.velocity)
    }
    private func add(beat: Double, pitch: Int) {
        guard let clip else { return }
        let index = clip.performance.notes.count
        if ensemble.editClipNotes(part: part.id, clip: clipID, change: {
            $0.append(PerformanceNote(beat: beat, duration: 0.5, pitch: pitch - clip.performance.transpose, velocity: 90))
        }) { select(index) }
    }
    private func update(_ index: Int, _ change: (inout PerformanceNote) -> Void) {
        if ensemble.editClipNotes(part: part.id, clip: clipID, change: { notes in
            if notes.indices.contains(index) { change(&notes[index]) }
        }) { select(index) }
    }
    var body: some View {
        if let clip {
            VStack(spacing: 0) {
                HStack {
                    Text("NOTE EDITOR").tracking(1.3)
                    Text(clip.performance.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("1 cycle · ×\(clip.repeatCount)").foregroundStyle(.secondary)
                    Button("Add Note") {
                        let root = part.instrument?.root ?? 60
                        let candidates = (max(0, root - 24)...min(127, root + 24)).sorted {
                            abs($0 - root) == abs($1 - root) ? $0 < $1 : abs($0 - root) < abs($1 - root)
                        }
                        let free = candidates.first { candidate in
                            !clip.performance.notes.contains { $0.channel == 0 && $0.pitch + clip.performance.transpose == candidate && $0.beat < 0.5 }
                        } ?? root
                        add(beat: 0, pitch: free)
                    }
                        .accessibilityLabel("Add clip note").disabled(clip.performance.notes.count >= 256)
                    Button("Delete") {
                        guard let selected else { return }
                        if ensemble.editClipNotes(part: part.id, clip: clipID, change: { notes in
                            if notes.indices.contains(selected) { notes.remove(at: selected) }
                        }) { self.selected = nil }
                    }.accessibilityLabel("Delete selected clip note").disabled(selected == nil || clip.performance.notes.count <= 1)
                }.font(.system(size: 10)).padding(.horizontal, 10).frame(height: 34)
                Divider()
                ClipNoteGrid(performance: clip.performance, root: part.instrument?.root ?? 60, selected: selected,
                             onSelect: select, onAdd: add, onChange: update)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        Text(selected.map { "NOTE \($0 + 1)" } ?? "Select a note").foregroundStyle(.secondary)
                        field("Pitch", value: $pitch, label: "Selected note pitch")
                        field("Start", value: $beat, label: "Selected note start")
                        field("Length", value: $duration, label: "Selected note length")
                        field("Velocity", value: $velocity, label: "Selected note velocity")
                        Button("Apply") {
                            guard let selected else { return }
                            guard let pitch = Int(pitch), let beat = Double(beat),
                                  let duration = Double(duration), let velocity = Int(velocity),
                                  (0...127).contains(pitch) else {
                                ensemble.error = "音程・開始拍・長さ・強弱を数値で入力してください。"; return
                            }
                            update(selected) { note in
                                note.pitch = pitch - clip.performance.transpose; note.beat = beat
                                note.duration = duration; note.velocity = velocity
                            }
                        }.accessibilityLabel("Apply selected note").disabled(selected == nil)
                        Text("\(clip.performance.notes.count) notes · MIDI pitch · Velocity before clip %").foregroundStyle(.secondary)
                    }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 5)
                }.fixedSize(horizontal: false, vertical: true).disabled(selected == nil)
                Text("Click empty grid to add · Drag note to move · Drag right edge to resize · Snap ¼ beat · All repeats follow")
                    .font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 20)
            }.background(Color(red: 0.105, green: 0.13, blue: 0.095))
                .overlay { Rectangle().stroke(.black.opacity(0.4), lineWidth: 1).allowsHitTesting(false) }
                .disabled(!ensemble.canEdit)
                .onChange(of: clip.performance) { _, _ in
                    if let selected {
                        if clip.performance.notes.indices.contains(selected) { select(selected) }
                        else { self.selected = nil }
                    }
                }
        }
    }
    private func field(_ title: String, value: Binding<String>, label: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            TextField(title, text: value)
                .textFieldStyle(.roundedBorder).frame(width: 54).accessibilityLabel(label)
        }
    }
}

private struct ClipNoteGrid: View {
    let performance: PerformanceDocument
    let root: Int
    let selected: Int?
    let onSelect: (Int) -> Void
    let onAdd: (Double, Int) -> Void
    let onChange: (Int, (inout PerformanceNote) -> Void) -> Void
    private var length: Double {
        max(4, ceil((try? PerformanceNoteLayout.make(performance, repeatCount: 1, root: root).length) ?? 4) + 1)
    }
    private var low: Int { max(0, min(root - 12, (performance.notes.map { $0.pitch + performance.transpose }.min() ?? root) - 2)) }
    private var high: Int { min(127, max(root + 12, (performance.notes.map { $0.pitch + performance.transpose }.max() ?? root) + 2)) }
    private func snap(_ value: Double) -> Double { (value * 4).rounded() / 4 }
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                let width = max(geometry.size.width - 42, min(20_600, length * 72))
                let height = max(geometry.size.height - 22, CGFloat(high - low + 1) * 8)
                let scale = width / length
                let row = height / Double(high - low + 1)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach((low...high).reversed(), id: \.self) { note in
                            Text(note % 12 == 0 ? NotePitch.name(note) : "").font(.system(size: 9, design: .monospaced))
                                .frame(width: 42, height: row).background(Color.white.opacity(note % 12 == 0 ? 0.06 : 0.02))
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            for note in low...high {
                                let y = Double(high - note) * row
                                if [1, 3, 6, 8, 10].contains(note % 12) {
                                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: row)), with: .color(.black.opacity(0.16)))
                                }
                                var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                            }
                            for value in stride(from: 0.0, through: length, by: 0.25) {
                                let x = value * scale
                                var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: height))
                                context.stroke(path, with: .color(.white.opacity(value.truncatingRemainder(dividingBy: 1) == 0 ? 0.15 : 0.04)), lineWidth: 0.5)
                                if value.truncatingRemainder(dividingBy: 1) == 0 {
                                    context.draw(Text("\(Int(value))").font(.system(size: 8)).foregroundColor(.gray), at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                                }
                            }
                        }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { tap in
                            let note = high - Int(tap.location.y / row)
                            onAdd(max(0, snap(tap.location.x / scale)), min(high, max(low, note)))
                        }).accessibilityLabel("Clip note grid").accessibilityValue("\(performance.notes.count) notes; one cycle; quarter beat snap")
                        ForEach(performance.notes.indices, id: \.self) { index in
                            let note = performance.notes[index]
                            let noteWidth = max(9, note.duration * scale)
                            HStack(spacing: 0) {
                                Button { onSelect(index) } label: {
                                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Clip note \(index + 1)")
                                    .accessibilityValue("Pitch \(note.pitch + performance.transpose), start \(note.beat), length \(note.duration), velocity \(note.velocity), channel \(note.channel + 1)")
                                    .highPriorityGesture(DragGesture(minimumDistance: 3).onEnded { drag in
                                        onChange(index) { value in
                                            value.beat = max(0, snap(note.beat + drag.translation.width / scale))
                                            value.pitch = note.pitch - Int((drag.translation.height / row).rounded())
                                        }
                                    })
                                Rectangle().fill(.white.opacity(0.35)).frame(width: min(6, noteWidth / 3))
                                    .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onEnded { drag in
                                        onChange(index) { $0.duration = max(0.25, snap(note.duration + drag.translation.width / scale)) }
                                    }).help("Drag to resize note")
                            }.frame(width: noteWidth, height: max(8, row - 2))
                                .background(Color(red: 0.88, green: 0.77, blue: 0.53).opacity(0.45 + Double(note.velocity) / 250))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay { RoundedRectangle(cornerRadius: 2).stroke(selected == index ? Color.white : .clear, lineWidth: 1) }
                                .offset(x: note.beat * scale, y: Double(high - note.pitch - performance.transpose) * row + 1)
                        }
                    }.frame(width: width, height: height).clipped()
                }
            }.defaultScrollAnchor(.topLeading)
        }
    }
}
