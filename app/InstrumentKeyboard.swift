import SwiftUI

struct InstrumentKeyboard: View {
    @ObservedObject var model: PlayerModel
    @State private var pressedScreenNote: Int?
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private let whiteNotes = (48...72).filter { ![1, 3, 6, 8, 10].contains($0 % 12) }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("INSTRUMENT").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Text("Root").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("Root note", selection: $model.rootNote) {
                    ForEach(48...72, id: \.self) { note in Text(NotePitch.name(note)).tag(note) }
                }.labelsHidden().frame(width: 76).controlSize(.small)
                Spacer(minLength: 0)
                Button("Open…") { model.openInstrumentPanel() }.buttonStyle(.bordered).controlSize(.small).help("Open Instrument · ⇧⌘O")
                Button("Save…") { model.saveInstrumentPanel() }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(model.instrumentSample == nil).help("Save Instrument · ⌘S")
                Button(model.editor.selection == nil ? "Use Full Sample" : "Use Selection") {
                    Task { await model.prepareInstrument() }
                }.buttonStyle(.bordered).controlSize(.small)
                Text(model.activeNotes.isEmpty ? "—" : "\(model.activeNotes.count) held")
                    .foregroundStyle(accent).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 90)
            }
            HStack(spacing: 12) {
                Toggle("Hold keys", isOn: $model.holdKeys).toggleStyle(.checkbox)
                    .help("ONで画面鍵盤をクリックして音を保持。もう一度クリックして離鍵。")
                Button(model.demoChordActive ? "Release chord" : "Demo chord") { model.toggleDemoChord() }
                    .controlSize(.small).disabled(model.instrumentSample == nil)
                    .help("基準音から長三和音を演奏。もう一度押すとRelease。")
                Button("All Notes Off") { model.stopInstrument() }.controlSize(.small)
                Spacer(minLength: 0)
                Text("\(model.soundingVoices)/8 voices · A–K: C4–C5").foregroundStyle(.secondary)
            }.font(.system(size: 10))
            MIDIControls(model: model, midi: model.midi)
            EnvelopeControls(model: model)
            LoopControls(model: model)
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(whiteNotes.count)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        ForEach(whiteNotes, id: \.self) { note in
                            key(note: note, black: false).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach((48...72).filter { [1, 3, 6, 8, 10].contains($0 % 12) }, id: \.self) { note in
                        let preceding = whiteNotes.filter { $0 < note }.count
                        key(note: note, black: true).frame(width: width * 0.62, height: geometry.size.height * 0.63)
                            .offset(x: CGFloat(preceding) * width - width * 0.31)
                    }
                }
            }.frame(height: 82)
            HStack {
                Text((model.instrumentDirty ? "● " : "") + (model.instrumentSample.map { "\($0.name) · \(String(format: "%.3f", Double($0.selection.startFrame) / $0.buffer.format.sampleRate))–\(String(format: "%.3f", Double($0.selection.endFrame) / $0.buffer.format.sampleRate)) s" } ?? "Choose a range, then Use Selection to load your instrument."))
                Spacer()
                Text("8 voices · Speed changes with pitch")
            }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .disabled(model.busy || model.asset == nil)
        .onDisappear { pressedScreenNote = nil; model.suspendMIDI(true) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.title == "SonicForge" {
                pressedScreenNote = nil; model.suspendMIDI(true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in pressedScreenNote = nil; model.suspendMIDI(true) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.title == "SonicForge" { model.suspendMIDI(false) }
        }
    }
    private func key(note: Int, black: Bool) -> some View {
        let active = model.activeNotes.contains(note)
        return VStack {
            if note == model.rootNote { Circle().fill(accent).frame(width: 4, height: 4).padding(.top, 7) }
            Spacer(minLength: 0)
            Text(NotePitch.name(note)).font(.system(size: black ? 8 : 9, weight: .medium))
                .foregroundStyle(active ? Color.black : black ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                .padding(.bottom, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? accent : black ? Color(red: 0.08, green: 0.10, blue: 0.12) : Color(red: 0.76, green: 0.79, blue: 0.80))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.5)) }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressedScreenNote != note { pressedScreenNote = note; model.screenKeyDown(note) }
            }
            .onEnded { _ in pressedScreenNote = nil; model.screenKeyUp(note) })
        .accessibilityLabel("Play " + NotePitch.name(note))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.screenKeyDown(note); model.screenKeyUp(note) }
        .disabled(model.instrumentSample == nil)
        .opacity(model.instrumentSample == nil ? 0.45 : 1)
    }
}

struct EnvelopeControls: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        HStack(spacing: 16) {
            parameter("ATTACK", keyPath: \.attack, seconds: true, help: "押鍵から最大音量になるまで。次の発音から反映。")
            parameter("DECAY", keyPath: \.decay, seconds: true, help: "最大音量からSustainまで下がる時間。")
            parameter("SUSTAIN", keyPath: \.sustain, seconds: false, help: "押している間の音量。元音源の自然な減衰は維持します。")
            parameter("RELEASE", keyPath: \.release, seconds: true, help: "離鍵後に消えるまで。ループOFF時は音源の末尾で先に停止します。")
        }.padding(.vertical, 4)
    }
    private func parameter(_ name: String, keyPath: WritableKeyPath<ADSRParameters, Double>, seconds: Bool, help: String) -> some View {
        let value = model.envelope[keyPath: keyPath]
        return VStack(spacing: 2) {
            HStack {
                Text(name).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(seconds ? String(format: "%.3f s", value) : String(format: "%.0f %%", value * 100))
                    .font(.system(size: 10, design: .monospaced))
            }
            Slider(value: Binding(get: { seconds ? sqrt(value / 5) : value }, set: { position in
                var parameters = model.envelope
                parameters[keyPath: keyPath] = seconds ? position * position * 5 : position
                model.setEnvelope(parameters)
            }), in: 0...1)
                .controlSize(.small).tint(Color(red: 0.96, green: 0.72, blue: 0.33))
                .accessibilityLabel(name)
                .accessibilityValue(seconds ? String(format: "%.3f seconds", value) : String(format: "%.0f percent", value * 100))
        }.help(help)
    }
}

struct LoopControls: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                Toggle("LOOP", isOn: Binding(get: { model.sampleLoop.enabled }, set: {
                    var loop = model.sampleLoop; loop.enabled = $0; model.setLoop(loop)
                })).toggleStyle(.checkbox).font(.system(size: 10, weight: .medium))
                    .help("次の発音から反映。離鍵後はループしながらReleaseで減衰します。")
                boundary("START", start: true)
                boundary("END", start: false)
                Button("From Selection") { model.loopFromSelection() }
                    .controlSize(.small).disabled(!model.canSetLoopFromSelection)
                    .help("波形の選択範囲をループに設定。取り込み済みサンプルの範囲内で選択してください。")
            }
            HStack(spacing: 10) {
                Text("CROSSFADE").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                let rate = model.instrumentSample?.buffer.format.sampleRate ?? 1
                let limit = max(1, min(Int64(rate * 0.1), (model.sampleLoop.endFrame - model.sampleLoop.startFrame) / 2))
                Slider(value: Binding(get: { Double(model.sampleLoop.crossfadeFrames) }, set: { value in
                    var loop = model.sampleLoop
                    loop.crossfadeFrames = Int64(value.rounded())
                    model.setLoop(loop)
                }), in: 0...Double(limit)).controlSize(.small)
                    .tint(Color(red: 0.96, green: 0.72, blue: 0.33))
                    .accessibilityLabel("Loop crossfade")
                    .accessibilityValue(String(format: "%.2f milliseconds", Double(model.sampleLoop.crossfadeFrames) / rate * 1000))
                Text(model.sampleLoop.crossfadeFrames == 0 ? "OFF" : String(format: "%.2f ms", Double(model.sampleLoop.crossfadeFrames) / rate * 1000))
                    .font(.system(size: 10, design: .monospaced)).frame(width: 72, alignment: .trailing)
            }.disabled(!model.sampleLoop.enabled)
                .help("ループ末尾と先頭を重ねて継ぎ目を滑らかにします。0でOFF。最大100 msまたはループの半分。次の発音から反映。")
        }
        .disabled(model.instrumentSample == nil)

    }
    private func boundary(_ label: String, start: Bool) -> some View {
        let sample = model.instrumentSample
        let rate = sample?.buffer.format.sampleRate ?? 1
        let count = Int64(sample?.buffer.frameLength ?? 2)
        let loop = model.sampleLoop
        return HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(start ? loop.startFrame : loop.endFrame) }, set: { value in
                var updated = model.sampleLoop
                if start { updated.startFrame = min(Int64(value.rounded()), updated.endFrame - 2) }
                else { updated.endFrame = max(Int64(value.rounded()), updated.startFrame + 2) }
                updated.crossfadeFrames = min(updated.crossfadeFrames, max(0, updated.endFrame - updated.startFrame) / 2)
                model.setLoop(updated)
            }), in: start ? 0...Double(max(1, count - 2)) : 2...Double(max(3, count)))
                .controlSize(.small).tint(Color(red: 0.96, green: 0.72, blue: 0.33))
                .accessibilityLabel("Loop " + label)
            Text(String(format: "%.3f s", Double(start ? loop.startFrame : loop.endFrame) / rate))
                .monospacedDigit().frame(width: 63, alignment: .trailing)
        }.font(.system(size: 9))
    }
}

struct MIDIControls: View {
    @State private var editingPerformance = false
    @ObservedObject var model: PlayerModel
    @ObservedObject var midi: MIDIInput
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Text("MIDI IN").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Picker("MIDI input", selection: Binding(get: { midi.selected }, set: { model.suspendMIDI(false); midi.select($0) })) {
                    Text("None").tag(UInt32(0))
                    ForEach(midi.sources) { source in Text(source.name).tag(source.id) }
                }.labelsHidden().controlSize(.small).frame(minWidth: 120, maxWidth: 230)
                Button("Refresh") { midi.start(); midi.refresh() }.controlSize(.small)
                Button("Test input") { model.suspendMIDI(false); midi.createTestInput() }.controlSize(.small)
                    .help("仮想MIDI送信元を作成して選択します。実機なしで同じ受信経路を確認できます。")
                if midi.testSource != 0 && midi.selected == midi.testSource {
                    Button(midi.testingChord ? "Release MIDI" : "MIDI chord") { midi.toggleTestChord() }
                        .controlSize(.small).disabled(model.instrumentSample == nil)
                }
                Spacer(minLength: 0)
                Text(midi.error ?? (midi.selected == 0 ? "Not connected" : model.midiSuspended ? "Paused" : "Omni · Root ±24 st"))
                    .foregroundStyle(midi.error == nil ? Color.secondary : Color.orange).lineLimit(1).help(midi.error ?? "MIDI 1.0 · 全チャンネル受信 · ベロシティ対応")
            }.font(.system(size: 9))
            HStack(spacing: 8) {
                if midi.testSource != 0 && midi.selected == midi.testSource {
                    Text("VELOCITY").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(midi.testVelocity) }, set: { midi.testVelocity = Int($0.rounded()) }), in: 1...127)
                        .controlSize(.small).frame(width: 90).accessibilityLabel("Test velocity")
                    Text("\(midi.testVelocity)").monospacedDigit().frame(width: 23)
                    Toggle("Test pedal", isOn: Binding(get: { model.sustainChannels.contains(0) }, set: { midi.stopPerformance(); midi.sendTest([0xB0, 64, $0 ? 127 : 0]) }))
                        .toggleStyle(.checkbox)
                    Divider().frame(height: 12)
                }
                Picker("Performance preset", selection: Binding<MIDIPerformancePreset?>(get: { midi.customPerformance ? nil : midi.performancePreset }, set: { if let preset = $0 { midi.performancePreset = preset } })) {
                    if midi.customPerformance { Text((midi.performanceDirty ? "● " : "") + midi.performance.name).tag(Optional<MIDIPerformancePreset>.none) }
                    ForEach(MIDIPerformancePreset.allCases) { preset in Text(preset.rawValue).tag(Optional(preset)) }
                }.labelsHidden().controlSize(.small).frame(width: 125).disabled(midi.performing)
                Button(midi.performing ? "Stop auto" : "Auto play") {
                    model.suspendMIDI(false)
                    if midi.performing { midi.stopPerformance() } else { midi.playPerformance() }
                }.controlSize(.small).disabled(model.instrumentSample == nil)
                    .help("演奏できなくてもプリセットで試聴できます。仮想MIDI入力へ切り替えて演奏します。")
                Button(midi.performanceDirty ? "Edit ●" : "Edit…") { editingPerformance = true }
                    .controlSize(.small).disabled(midi.performing)
                Spacer(minLength: 0)
                Text(model.sustainChannels.isEmpty ? "PEDAL OFF" : "PEDAL CH " + model.sustainChannels.sorted().map { String(Int($0) + 1) }.joined(separator: ","))
                    .foregroundStyle(model.sustainChannels.isEmpty ? Color.secondary : Color.orange).lineLimit(1)
            }.font(.system(size: 9))
        }.sheet(isPresented: $editingPerformance) { PerformanceEditor(midi: midi) }
    }
}
