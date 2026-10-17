import SwiftUI

struct EnsembleView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmOpen = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent)
                Text("Ensemble").font(.system(size: 22, weight: .medium))
                Text("\(ensemble.parts.count) / 4 parts").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(ensemble.dirty ? "● Unsaved" : ensemble.fileURL == nil ? "New" : "Saved")
                    .font(.system(size: 11)).foregroundStyle(ensemble.dirty ? accent : .secondary)
                Spacer()
                if ensemble.busy { ProgressView().controlSize(.small) }
                Button("Open…") { if ensemble.dirty { confirmOpen = true } else { ensemble.openPanel() } }
                    .buttonStyle(StudioButton()).disabled(!ensemble.canEdit).accessibilityLabel("Open ensemble")
                Button("Save…") { ensemble.savePanel() }.buttonStyle(StudioButton())
                    .disabled(!ensemble.canEdit || ensemble.parts.isEmpty).accessibilityLabel("Save ensemble")
                Button("Done") { ensemble.stop(); dismiss() }.buttonStyle(StudioButton())
            }
            HStack {
                Button("Add Part") { ensemble.addPart() }
                Button("Add Current") {
                    if let instrument = currentInstrument {
                        ensemble.addPart(instrument: instrument, performance: model.midi.performance)
                    }
                }.disabled(model.instrumentSample == nil || model.busy)
                Spacer()
                Button("Add Demo Duo") { Task { await ensemble.addDemos() } }.disabled(ensemble.parts.count > 2)
            }.buttonStyle(StudioButton()).disabled(!ensemble.canEdit || ensemble.parts.count >= 4)
            Text(ensemble.fileMessage ?? ensemble.fileURL?.lastPathComponent ?? "Untitled ensemble · Save to keep this setup")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if ensemble.parts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "pianokeys").font(.system(size: 36)).foregroundStyle(accent)
                    Text("Build a small ensemble").font(.system(size: 18, weight: .medium))
                    Text("Assign an instrument and a performance to each part, or try Add Demo Duo.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ensemble.parts) { part in
                            EnsemblePartRow(part: part, ensemble: ensemble, library: library,
                                            currentPerformance: model.midi.performance)
                        }
                    }.padding(.vertical, 2)
                }
            }
            Divider()
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TEMPO").font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack {
                        TextField("Ensemble tempo", value: $ensemble.tempo, format: .number).frame(width: 55).textFieldStyle(.roundedBorder)
                        Text("BPM").foregroundStyle(.secondary)
                    }.font(.system(size: 12)).disabled(!ensemble.canEdit)
                }
                Button(ensemble.playing ? "Stop All" : "Play All") {
                    if ensemble.playing { ensemble.stop() }
                    else { model.stop(); ensemble.play() }
                }.buttonStyle(StudioButton(primary: true)).disabled(ensemble.busy || ensemble.parts.isEmpty)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ensemble.playing ? (ensemble.releasing ? "Release tails…" : String(format: "Beat %.1f / %.1f", ensemble.positionBeats, ensemble.durationBeats)) : "Ready · Shared tempo")
                    ProgressView(value: ensemble.positionBeats, total: max(1, ensemble.durationBeats)).tint(accent)
                }.font(.system(size: 11)).frame(width: 200)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "MASTER · %.0f dB", ensemble.masterDB)).font(.system(size: 10))
                    Slider(value: $ensemble.masterDB, in: -60...0).frame(width: 130).tint(accent).accessibilityLabel("Ensemble master volume").disabled(ensemble.busy)
                    Text("Output \(Int(ensemble.level)) dB").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if let error = ensemble.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3).help(error) }
            Text("Save includes all instruments, performances, levels and tempo. The last saved or opened ensemble restores on launch.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 880, height: 650)
            .background(Color(red: 0.075, green: 0.09, blue: 0.105)).preferredColorScheme(.dark)
            .confirmationDialog("Replace unsaved ensemble changes?", isPresented: $confirmOpen) {
                Button("Choose Ensemble…", role: .destructive) { ensemble.openPanel() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Cancel and save this ensemble first to keep your changes. A failed read keeps the current ensemble.") }
            .onDisappear { ensemble.stop() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in ensemble.stop() }
    }
    private var currentInstrument: EnsembleInstrument? {
        guard let sample = model.instrumentSample else { return nil }
        return EnsembleInstrument(sample: sample, root: model.rootNote, envelope: model.envelope,
                                  loop: model.sampleLoop, name: model.instrumentFileURL?.deletingPathExtension().lastPathComponent ?? sample.name)
    }
}

private struct EnsemblePartRow: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    let currentPerformance: PerformanceDocument
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Part name", text: $part.name).font(.system(size: 14, weight: .medium)).textFieldStyle(.plain)
                    .disabled(!ensemble.canEdit)
                Spacer()
                Text("\(part.voices)/8 voices").font(.system(size: 10, design: .monospaced)).foregroundStyle(accent)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.black.opacity(0.3))
                        Rectangle().fill(accent).frame(width: geometry.size.width * CGFloat(max(0, min(1, (part.level + 60) / 60))))
                    }
                }.frame(width: 70, height: 5).accessibilityLabel("\(part.name) output \(Int(part.level)) decibels")
                Button("Remove") { ensemble.remove(part.id) }.disabled(!ensemble.canEdit)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("INSTRUMENT").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack {
                        Picker("Instrument for \(part.name)", selection: Binding<URL?>(get: { part.instrumentURL }, set: { url in
                            if let url { Task { await ensemble.loadInstrument(url, part: part.id) } }
                        })) {
                            Text(part.instrumentURL == nil ? (part.instrument?.name ?? "Choose instrument") : "Choose instrument")
                                .tag(Optional<URL>.none)
                            ForEach(library.entries) { entry in
                                Text(entry.name + (entry.available ? "" : " · Missing")).tag(Optional(entry.url))
                            }
                            if let url = part.instrumentURL, !library.entries.contains(where: { $0.url == url }) {
                                Text(part.instrument?.name ?? url.lastPathComponent).tag(Optional(url))
                            }
                        }.labelsHidden().frame(width: 220)
                        Button("Open…") { ensemble.openInstrument(part.id) }.accessibilityLabel("Open instrument for \(part.name)")
                    }
                    Text(part.instrument.map { "Root \(NotePitch.name($0.root)) · \($0.loop.enabled ? "Loop" : "One-shot")" } ?? "Select from library or open a saved instrument")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(width: 300, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text("PERFORMANCE").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack {
                        Text(part.performance.name).font(.system(size: 12)).lineLimit(1).frame(width: 180, alignment: .leading)
                        Menu("Preset") {
                            ForEach(MIDIPerformancePreset.allCases) { preset in
                                Button(preset.rawValue) { ensemble.setPerformance(.preset(preset), part: part.id) }
                            }
                        }.frame(width: 65)
                        Button("Open…") { ensemble.openPerformance(part.id) }.accessibilityLabel("Open performance for \(part.name)")
                        Button("Use Current") { ensemble.setPerformance(currentPerformance, part: part.id) }
                            .help("Assign a snapshot of the studio performance, including AI-generated data")
                    }
                    Text("\(part.performance.notes.count) notes · Follows ensemble tempo")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.disabled(!ensemble.canEdit)
            HStack {
                Toggle("Mute", isOn: $part.muted).toggleStyle(.checkbox)
                Slider(value: $part.gainDB, in: -36...0).frame(width: 145).tint(accent).accessibilityLabel("\(part.name) volume")
                Text(String(format: "%.0f dB", part.gainDB)).monospacedDigit().frame(width: 40)
                Spacer()
                Text(validation ?? "Ready").foregroundStyle(validation == nil ? Color.secondary : .orange).lineLimit(1)
            }.disabled(ensemble.busy).font(.system(size: 10))
        }.controlSize(.small).padding(14)
            .background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)) }
    }
    private var validation: String? {
        guard let instrument = part.instrument else { return "Assign an instrument" }
        do { _ = try part.performance.events(root: instrument.root); return nil }
        catch { return error.localizedDescription }
    }
}
