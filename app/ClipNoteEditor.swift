import SwiftUI
import AppKit

/// One cycle is edited; clip repeats are generated from this same source document.
struct SelectedClipNotes: View {
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var part: EnsemblePart
    let clipID: UUID
    @State private var selection: Set<Int> = []
    @State private var multiSelect = false
    @State private var moveBeats = "1"
    @State private var movePitch = "0"
    private var selected: Int? { selection.count == 1 ? selection.first : nil }
    @State private var pitch = "60"
    @State private var beat = "0"
    @State private var duration = "1"
    @State private var velocity = "90"
    private var clip: EnsembleClip? { part.allClips.first { $0.id == clipID } }
    private var accent: Color { Color(red: 0.90, green: 0.78, blue: 0.51) }
    private func select(_ index: Int) {
        guard let clip, clip.performance.notes.indices.contains(index) else { return }
        selection = [index]
        let note = clip.performance.notes[index]
        pitch = String(note.pitch + clip.performance.transpose); beat = String(note.beat)
        duration = String(note.duration); velocity = String(note.velocity)
    }
    private func toggle(_ index: Int) {
        if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
        if let only = selected { select(only) }
    }
    private func pick(_ index: Int) {
        if multiSelect { toggle(index) } else { select(index) }
    }
    private func group(_ action: EnsembleModel.NoteGroupAction) {
        if let result = ensemble.editNoteGroup(part: part.id, clip: clipID, indices: selection, action: action) {
            selection = result
            if let only = selected { select(only) }
        }
    }
    private func offsetAction(duplicate: Bool) {
        guard let beats = Double(moveBeats), let pitch = Int(movePitch) else {
            ensemble.error = "移動量を数値で入力してください。"; return
        }
        group(duplicate ? .duplicate(beats, pitch) : .move(beats, pitch))
    }
    private func move(_ index: Int, beats: Double, pitch: Int) {
        if !selection.contains(index) { selection = [index] }
        group(.move(beats, pitch))
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
                    Button {
                        if ensemble.restoreNoteEdit(part: part.id, clip: clipID) { selection = [] }
                    } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityLabel("Undo clip note edit").help("Undo this clip’s last note edit")
                        .disabled(!ensemble.canUndoNotes(part: part.id, clip: clipID))
                    Button {
                        if ensemble.restoreNoteEdit(part: part.id, clip: clipID, redo: true) { selection = [] }
                    } label: { Image(systemName: "arrow.uturn.forward") }
                        .accessibilityLabel("Redo clip note edit").help("Redo this clip’s note edit")
                        .disabled(!ensemble.canRedoNotes(part: part.id, clip: clipID))
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
                    Button("Delete") { group(.delete) }
                        .accessibilityLabel("Delete selected clip notes").disabled(selection.isEmpty || selection.count >= clip.performance.notes.count)
                }.font(.system(size: 10)).padding(.horizontal, 10).frame(height: 34)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        Toggle("Multi", isOn: $multiSelect).toggleStyle(.button).accessibilityLabel("Multiple note selection")
                        Button("All") { selection = Set(clip.performance.notes.indices) }.accessibilityLabel("Select all clip notes")
                        Button("Clear") { selection = [] }.accessibilityLabel("Clear note selection")
                        Text("\(selection.count) selected").foregroundStyle(.secondary).accessibilityLabel("Selected note count").accessibilityValue("\(selection.count)")
                        field("Δ beats", value: $moveBeats, label: "Selected notes beat offset")
                        field("Δ pitch", value: $movePitch, label: "Selected notes pitch offset")
                        Button("Move") { offsetAction(duplicate: false) }.accessibilityLabel("Move selected clip notes").disabled(selection.isEmpty)
                        Button("Duplicate") { offsetAction(duplicate: true) }.accessibilityLabel("Duplicate selected clip notes").disabled(selection.isEmpty)
                    }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 4)
                }.fixedSize(horizontal: false, vertical: true)
                Divider()
                ClipNoteGrid(performance: clip.performance, root: part.instrument?.root ?? 60, selected: selection, selectionMode: multiSelect,
                             onSelect: pick, onToggle: toggle, onSelectRange: { selection = $0 }, onAdd: add, onChange: update, onMove: move)
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
                Text("Shift-click or Multi to select · Drag empty grid to select a range · Drag selected notes to move · Snap ¼ beat")
                    .font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 20)
            }.background(Color(red: 0.105, green: 0.13, blue: 0.095))
                .overlay { Rectangle().stroke(.black.opacity(0.4), lineWidth: 1).allowsHitTesting(false) }
                .disabled(!ensemble.canEdit)
                .onChange(of: clip.performance) { old, new in
                    // Preserve our updated indices; discard a stale selection on external replacement or undo.
                    if old.notes.count == new.notes.count {
                        selection = selection.filter { new.notes.indices.contains($0) }
                        if let only = selected { select(only) }
                    } else { selection = selection.filter { new.notes.indices.contains($0) } }
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
    let selected: Set<Int>
    let selectionMode: Bool
    @State private var marquee: CGRect?
    let onSelect: (Int) -> Void
    let onToggle: (Int) -> Void
    let onSelectRange: (Set<Int>) -> Void
    let onAdd: (Double, Int) -> Void
    let onChange: (Int, (inout PerformanceNote) -> Void) -> Void
    let onMove: (Int, Double, Int) -> Void
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
                            if selectionMode || NSEvent.modifierFlags.contains(.shift) { onSelectRange([]) }
                            else { onAdd(max(0, snap(tap.location.x / scale)), min(high, max(low, note))) }
                        }).simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { drag in
                            marquee = CGRect(x: min(drag.startLocation.x, drag.location.x), y: min(drag.startLocation.y, drag.location.y),
                                             width: abs(drag.translation.width), height: abs(drag.translation.height))
                        }.onEnded { _ in
                            guard let rect = marquee else { return }; marquee = nil
                            let found = Set(performance.notes.indices.filter { index in
                                let note = performance.notes[index]
                                return rect.intersects(CGRect(x: note.beat * scale, y: Double(high - note.pitch - performance.transpose) * row,
                                                              width: max(9, note.duration * scale), height: row))
                            })
                            onSelectRange(NSEvent.modifierFlags.contains(.shift) ? selected.union(found) : found)
                        }).accessibilityLabel("Clip note grid").accessibilityValue("\(performance.notes.count) notes; one cycle; quarter beat snap")
                        ForEach(performance.notes.indices, id: \.self) { index in
                            let note = performance.notes[index]
                            let noteWidth = max(9, note.duration * scale)
                            HStack(spacing: 0) {
                                Button { onSelect(index) } label: {
                                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Clip note \(index + 1)")
                                    .accessibilityValue("Pitch \(note.pitch + performance.transpose), start \(note.beat), length \(note.duration), velocity \(note.velocity), channel \(note.channel + 1), \(selected.contains(index) ? "selected" : "unselected")")
                                    .highPriorityGesture(DragGesture(minimumDistance: 3)
                                        .exclusively(before: TapGesture().modifiers(.shift))
                                        .onEnded { result in
                                            switch result {
                                            case let .first(drag): onMove(index, snap(drag.translation.width / scale), -Int((drag.translation.height / row).rounded()))
                                            case .second: onToggle(index)
                                            }
                                        })
                                Rectangle().fill(.white.opacity(0.35)).frame(width: min(6, noteWidth / 3))
                                    .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onEnded { drag in
                                        guard selected.count <= 1 else { return }
                                        onChange(index) { $0.duration = max(0.25, snap(note.duration + drag.translation.width / scale)) }
                                    }).help("Drag to resize note")
                            }.frame(width: noteWidth, height: max(8, row - 2))
                                .background(Color(red: 0.88, green: 0.77, blue: 0.53).opacity(0.45 + Double(note.velocity) / 250))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay { RoundedRectangle(cornerRadius: 2).stroke(selected.contains(index) ? Color.white : .clear, lineWidth: 1) }
                                .offset(x: note.beat * scale, y: Double(high - note.pitch - performance.transpose) * row + 1)
                        }
                        if let marquee {
                            Rectangle().fill(Color.yellow.opacity(0.12)).overlay { Rectangle().stroke(Color.yellow.opacity(0.6), lineWidth: 1) }
                                .frame(width: marquee.width, height: marquee.height).offset(x: marquee.minX, y: marquee.minY).allowsHitTesting(false)
                        }
                    }.frame(width: width, height: height).clipped()
                }
            }.defaultScrollAnchor(.topLeading)
        }
    }
}
