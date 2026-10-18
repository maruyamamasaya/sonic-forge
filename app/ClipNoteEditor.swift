import SwiftUI
import AppKit

/// One cycle is edited; clip repeats are generated from this same source document.
struct SelectedClipNotes: View {
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var part: EnsemblePart
    let clipID: UUID
    @State private var selection: Set<Int> = []
    @State private var pasteBeat = "0"
    @State private var multiSelect = false
    @State private var scaleLengths = false
    @State private var groupLength = "1"
    @State private var relativeVelocity = false
    @State private var groupVelocity = "90"
    @State private var quantizeGrid: NoteQuantizeGrid = .sixteenth
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
                        .accessibilityIdentifier("Undo clip note edit").accessibilityLabel("音符編集を取り消す").help("このクリップの音符編集を1操作戻します。構成全体の取り消しではありません。")
                        .disabled(!ensemble.canUndoNotes(part: part.id, clip: clipID))
                    Button {
                        if ensemble.restoreNoteEdit(part: part.id, clip: clipID, redo: true) { selection = [] }
                    } label: { Image(systemName: "arrow.uturn.forward") }
                        .accessibilityIdentifier("Redo clip note edit").accessibilityLabel("音符編集をやり直す").help("取り消した音符編集をやり直します。")
                        .disabled(!ensemble.canRedoNotes(part: part.id, clip: clipID))
                    Text("音符編集").tracking(1.3)
                    Text(clip.performance.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("1周を編集・×\(clip.repeatCount)").foregroundStyle(.secondary)
                    Button("音符追加") {
                        let root = part.instrument?.root ?? 60
                        let candidates = (max(0, root - 24)...min(127, root + 24)).sorted {
                            abs($0 - root) == abs($1 - root) ? $0 < $1 : abs($0 - root) < abs($1 - root)
                        }
                        let free = candidates.first { candidate in
                            !clip.performance.notes.contains { $0.channel == 0 && $0.pitch + clip.performance.transpose == candidate && $0.beat < 0.5 }
                        } ?? root
                        add(beat: 0, pitch: free)
                    }
                        .accessibilityIdentifier("Add clip note").accessibilityLabel("音符を追加").disabled(clip.performance.notes.count >= 256)
                    Button("削除") { group(.delete) }
                        .accessibilityIdentifier("Delete selected clip notes").accessibilityLabel("選択した音符を削除").disabled(selection.isEmpty || selection.count >= clip.performance.notes.count)
                }.font(.system(size: 10)).padding(.horizontal, 10).frame(height: 34)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        Toggle("複数選択", isOn: $multiSelect).toggleStyle(.button).accessibilityIdentifier("Multiple note selection").accessibilityLabel("音符の複数選択")
                        Button("すべて") { selection = Set(clip.performance.notes.indices) }.accessibilityIdentifier("Select all clip notes").accessibilityLabel("すべての音符を選択")
                        Button("解除") { selection = [] }.accessibilityIdentifier("Clear note selection").accessibilityLabel("音符の選択を解除")
                        Text("\(selection.count) 選択中").foregroundStyle(.secondary).accessibilityIdentifier("Selected note count").accessibilityLabel("選択した音符数").accessibilityValue("\(selection.count)")
                        Button("コピー") { _ = ensemble.copyClipNotes(part: part.id, clip: clipID, indices: selection) }
                            .accessibilityIdentifier("Copy selected clip notes").accessibilityLabel("選択音符をコピー").disabled(selection.isEmpty)
                        field("貼付位置", value: $pasteBeat, label: "音符の貼り付け開始拍")
                        Button("貼り付け") {
                            guard let at = Double(pasteBeat) else { ensemble.error = "貼り付け位置を拍数で入力してください。"; return }
                            if let result = ensemble.pasteClipNotes(part: part.id, clip: clipID, at: at) {
                                selection = result
                                if let only = selected { select(only) }
                            }
                        }.accessibilityIdentifier("Paste copied clip notes").accessibilityLabel("コピーした音符を貼り付け").disabled(ensemble.copiedNotes.isEmpty)
                        Text("\(ensemble.copiedNotes.count) コピー済み").foregroundStyle(.secondary)
                            .accessibilityIdentifier("Copied note count").accessibilityLabel("コピーした音符数").accessibilityValue("\(ensemble.copiedNotes.count)")
                        Divider().frame(height: 16)
                        field("移動拍", value: $moveBeats, label: "音符の移動量・拍")
                        field("移動音程", value: $movePitch, label: "音符の移動量・半音")
                        Button("移動") { offsetAction(duplicate: false) }.accessibilityIdentifier("Move selected clip notes").accessibilityLabel("選択音符を移動").disabled(selection.isEmpty)
                        Button("複製") { offsetAction(duplicate: true) }.accessibilityIdentifier("Duplicate selected clip notes").accessibilityLabel("選択音符を複製").disabled(selection.isEmpty)
                        Divider().frame(height: 16)
                        Picker("刻み", selection: $quantizeGrid) {
                            ForEach(NoteQuantizeGrid.allCases) { grid in Text(grid.rawValue).tag(grid) }
                        }.frame(width: 112).accessibilityIdentifier("Note quantize grid").accessibilityLabel("拍に揃える細かさ")
                        Button("拍に揃える") { group(.quantize(quantizeGrid)) }
                            .accessibilityIdentifier("Quantize selected clip notes").accessibilityLabel("選択音符の開始を拍に揃える").disabled(selection.isEmpty)
                            .help("音符の開始だけを指定した刻みに揃えます。長さと強弱は保ちます。Tは3連符です。")
                        Divider().frame(height: 16)
                        Picker("強弱", selection: $relativeVelocity) {
                            Text("指定値").tag(false)
                            Text("増減").tag(true)
                        }.frame(width: 135).accessibilityIdentifier("Selected notes velocity mode").accessibilityLabel("音符の強弱の変更方法")
                            .onChange(of: relativeVelocity) { _, relative in groupVelocity = relative ? "0" : "90" }
                        TextField("値", text: $groupVelocity).textFieldStyle(.roundedBorder).frame(width: 48)
                            .accessibilityIdentifier("Selected notes velocity value").accessibilityLabel("音符の強弱の値")
                        Button("強弱を適用") {
                            guard let value = Int(groupVelocity) else {
                                ensemble.error = "ベロシティは整数で入力してください。"; return
                            }
                            group(relativeVelocity ? .velocityOffset(value) : .velocity(value))
                        }.accessibilityIdentifier("Apply velocity to selected notes").accessibilityLabel("選択音符の強弱をまとめて変更").disabled(selection.isEmpty)
                            .help("指定値は1〜127、増減は−126〜126。結果は1〜127に収めます。クリップ全体の強弱倍率を掛ける前の値です。")
                        Divider().frame(height: 16)
                        Picker("長さ", selection: $scaleLengths) {
                            Text("拍で指定").tag(false)
                            Text("比率で伸縮").tag(true)
                        }.frame(width: 150).accessibilityIdentifier("Selected notes length mode").accessibilityLabel("音符の長さの変更方法")
                            .onChange(of: scaleLengths) { _, scale in groupLength = scale ? "100" : "1" }
                        TextField(scaleLengths ? "%" : "拍", text: $groupLength).textFieldStyle(.roundedBorder).frame(width: 48)
                            .accessibilityIdentifier("Selected notes length value").accessibilityLabel("音符の長さの値")
                        Button("長さを適用") {
                            guard let value = Double(groupLength) else {
                                ensemble.error = "長さは数値で入力してください。"; return
                            }
                            group(scaleLengths ? .durationScale(value / 100) : .duration(value))
                        }.accessibilityIdentifier("Apply length to selected notes").accessibilityLabel("選択音符の長さをまとめて変更").disabled(selection.isEmpty)
                            .help("拍で指定すると同じ長さに揃えます。比率50%で半分、200%で2倍。開始位置を保ち、同音の重なりは拒否します。")
                    }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 4)
                }.fixedSize(horizontal: false, vertical: true)
                Divider()
                ClipNoteGrid(performance: clip.performance, root: part.instrument?.root ?? 60, selected: selection, selectionMode: multiSelect,
                             onSelect: pick, onToggle: toggle, onSelectRange: { selection = $0 }, onAdd: add, onChange: update, onMove: move)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        Text(selected.map { "音符 \($0 + 1)" } ?? "音符を選択").foregroundStyle(.secondary)
                        field("音程", value: $pitch, label: "音符の音程・MIDI番号")
                        field("開始", value: $beat, label: "音符の開始拍")
                        field("長さ", value: $duration, label: "音符の長さ・拍")
                        field("強弱", value: $velocity, label: "音符の強弱")
                        Button("適用") {
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
                        }.accessibilityIdentifier("Apply selected note").accessibilityLabel("選択音符の変更を適用").disabled(selected == nil)
                        Text("\(clip.performance.notes.count) 音符・音程はMIDI番号・強弱は倍率適用前").foregroundStyle(.secondary)
                    }.font(.system(size: 10)).padding(.horizontal, 10).padding(.vertical, 5)
                }.fixedSize(horizontal: false, vertical: true).disabled(selected == nil)
                Text("Shiftクリックか複数選択で選ぶ · 空白ドラッグで範囲選択 · 音符ドラッグで移動 · ¼拍刻み")
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
                .textFieldStyle(.roundedBorder).frame(width: 54).accessibilityLabel(label).help(JapaneseUI.fieldHelp(title))
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
                        }).accessibilityIdentifier("Clip note grid").accessibilityLabel("音符の編集グリッド").accessibilityValue("\(performance.notes.count) 音符・1周分・¼拍刻み")
                        ForEach(performance.notes.indices, id: \.self) { index in
                            let note = performance.notes[index]
                            let noteWidth = max(9, note.duration * scale)
                            HStack(spacing: 0) {
                                Button { onSelect(index) } label: {
                                    Rectangle().fill(Color.clear).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityIdentifier("Clip note \(index + 1)").accessibilityLabel("音符 \(index + 1)")
                                    .accessibilityValue("音程 \(note.pitch + performance.transpose)・開始 \(note.beat)拍・長さ \(note.duration)拍・強弱 \(note.velocity)・チャンネル \(note.channel + 1)・\(selected.contains(index) ? "選択中" : "未選択")")
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
                                    }).help("ドラッグで音符の長さを変更")
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
