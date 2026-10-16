import SwiftUI

struct InstrumentKeyboard: View {
    @ObservedObject var model: PlayerModel
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
                Text(model.activeNote.map { NotePitch.name($0) + String(format: "  %+d st", $0 - model.rootNote) } ?? "—")
                    .foregroundStyle(accent).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 90)
            }
            EnvelopeControls(model: model)
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
                Text("Mono voice · Hold to play · Speed changes with pitch")
            }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .disabled(model.busy || model.asset == nil)
        .onDisappear { model.stopInstrument() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in model.stopInstrument() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.stopInstrument() }
    }
    private func key(note: Int, black: Bool) -> some View {
        let active = model.activeNote == note
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
            .onChanged { _ in if model.activeNote != note { model.playNote(note) } }
            .onEnded { _ in model.releaseNote(note) })
        .accessibilityLabel("Play " + NotePitch.name(note))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.playNote(note) }
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
            parameter("RELEASE", keyPath: \.release, seconds: true, help: "離鍵後に消えるまで。音源の末尾では先に停止します。")
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
