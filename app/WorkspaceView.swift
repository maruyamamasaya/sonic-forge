import SwiftUI
import AppKit

extension Notification.Name { static let openEnsembleWorkspace = Notification.Name("SonicForge.openEnsembleWorkspace") }

struct WorkspaceView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    @State private var selectedPart: UUID?
    @State private var selectedClip: UUID?
    @State private var librarySelection: String?
    @State private var confirmOpen = false
    @State private var allParts = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var part: EnsemblePart? { ensemble.parts.first { $0.id == selectedPart } ?? ensemble.parts.first }
    private var activeClip: UUID? {
        guard let part else { return nil }
        return part.allClips.first(where: { $0.id == selectedClip })?.id ?? part.primaryClipID
    }
    private var entry: LibraryEntry? { library.filtered.first { $0.id == librarySelection } }
    var body: some View {
        Group {
            if model.ensembleWorkspaceActive { workspace }
            else { StudioView(model: model, onShowEnsemble: { model.stop(); library.stopPreview(); model.ensembleWorkspaceActive = true }) }
        }
        .onAppear { model.suspendMIDI(model.ensembleWorkspaceActive) }
        .onChange(of: model.ensembleWorkspaceActive) { _, active in
            ensemble.stop(); model.stop(); library.stopPreview(); model.suspendMIDI(active)
        }
        .onChange(of: ensemble.parts.map(\.id)) { _, _ in
            if !ensemble.parts.contains(where: { $0.id == selectedPart }) {
                selectedPart = ensemble.parts.first?.id; selectedClip = ensemble.parts.first?.primaryClipID
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openEnsembleWorkspace)) { _ in requestOpen() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in ensemble.stop(); library.stopPreview() }
        .onChange(of: library.query) { _, _ in librarySelection = nil; library.stopPreview() }
        .onDisappear { ensemble.stop(); library.stopPreview(); model.stop() }
        .sheet(isPresented: $allParts) { EnsembleView(model: model, ensemble: ensemble, library: library) }
        .confirmationDialog("Replace unsaved ensemble changes?", isPresented: $confirmOpen) {
            Button("Choose Ensemble…", role: .destructive) { ensemble.openPanel() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Cancel and save this ensemble first to keep your changes. A failed read keeps the current ensemble.") }
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                libraryPanel.frame(width: 210)
                Divider()
                VStack(spacing: 12) {
                    EnsembleSectionsView(ensemble: ensemble)
                    if ensemble.parts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "pianokeys").font(.system(size: 38)).foregroundStyle(accent)
                            Text("Build your arrangement").font(.system(size: 21, weight: .medium))
                            Text("Choose an instrument from the library, or start with Demo Song.").foregroundStyle(.secondary)
                            Button("Demo Song") { Task { await ensemble.addSharedSongDemo() } }
                                .disabled(!ensemble.sections.isEmpty || !ensemble.canEdit)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical) {
                            EnsembleTimelineView(ensemble: ensemble, expanded: true, selectedPart: part?.id,
                                                 selectedClip: activeClip, onSelect: select)
                                .frame(maxWidth: .infinity, minHeight: 390, alignment: .top)
                        }
                    }
                    HStack {
                        Button("Add Part") { if let added = ensemble.addPart() { select(added.id, added.primaryClipID) } }
                        Button("Add Current") { if let instrument = currentInstrument, let added = ensemble.addPart(instrument: instrument, performance: model.midi.performance) { select(added.id, added.primaryClipID) } }
                            .disabled(currentInstrument == nil || model.busy)
                        Spacer()
                        Menu("Demos") {
                            Button("Add Demo Duo") { Task { await ensemble.addDemos() } }
                            Button("Demo Entry +4") { Task { await ensemble.addDemos(staggered: true) } }
                            Button("Demo Repeat") { Task { await ensemble.addDemos(staggered: true, repeating: true) } }
                        }.frame(width: 85).disabled(ensemble.parts.count > 2)
                    }.disabled(!ensemble.canEdit || ensemble.parts.count >= 4)
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("INSPECTOR").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(.secondary).padding(16)
                    if let part {
                        WorkspaceInspector(part: part, ensemble: ensemble, currentPerformance: model.midi.performance,
                                           clipID: activeClip ?? part.primaryClipID)
                            .id(part.id)
                    } else {
                        Text("Select a part or clip").foregroundStyle(.secondary).padding(16)
                        Spacer()
                    }
                }.frame(width: 278).background(Color.white.opacity(0.025))
            }.frame(maxHeight: .infinity)
            Divider()
            transport
            if ensemble.exporting {
                HStack {
                    ProgressView(value: ensemble.exportProgress).tint(accent)
                    Text("Rendering \(Int(ensemble.exportProgress * 100))%")
                    Button("Cancel Export") { ensemble.cancelExport() }
                }.font(.system(size: 11)).padding(.horizontal, 20).padding(.bottom, 10)
            }
            HStack {
                Text(ensemble.error ?? library.error ?? ensemble.fileMessage ?? "Select a clip · Space to play / stop")
                    .foregroundStyle(ensemble.error == nil && library.error == nil ? Color.secondary : .orange).lineLimit(2)
                    .help(ensemble.error ?? library.error ?? "")
                Spacer()
                Text("\(ensemble.parts.count)/4 parts · \(ensemble.sections.count)/8 sections").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 16).padding(.vertical, 7)
        }.background(Color(red: 0.075, green: 0.085, blue: 0.10)).preferredColorScheme(.dark)
            .buttonStyle(StudioButton()).controlSize(.small)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent)
            Text("SonicForge").font(.system(size: 18, weight: .medium))
            Text("Ensemble").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider().frame(height: 20)
            Text(ensemble.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled ensemble").lineLimit(1).truncationMode(.middle)
            Text(ensemble.dirty ? "● Unsaved" : ensemble.fileURL == nil ? "New" : "Saved").foregroundStyle(ensemble.dirty ? accent : .secondary)
            Spacer()
            if ensemble.busy { ProgressView().controlSize(.small) }
            Button("All Parts…") { library.stopPreview(); ensemble.stop(); allParts = true }.disabled(ensemble.busy)
            Button("Open…") { requestOpen() }.disabled(!ensemble.canEdit).accessibilityLabel("Open ensemble")
            Button("Save…") { ensemble.savePanel() }.disabled(!ensemble.canEdit || ensemble.parts.isEmpty).accessibilityLabel("Save ensemble")
            Button("Export WAV…") { library.stopPreview(); ensemble.exportPanel(protecting: model.asset.map { [$0.url] } ?? []) }
                .disabled(!ensemble.canEdit || ensemble.parts.isEmpty)
        }.font(.system(size: 11)).padding(.horizontal, 18).frame(height: 60)
    }
    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INSTRUMENT LIBRARY").font(.system(size: 10, weight: .medium)).tracking(1.2)
            TextField("Search instruments", text: $library.query).textFieldStyle(.roundedBorder)
            HStack {
                Button("Files…") { library.addPanel() }.accessibilityLabel("Add Files…")
                Button("Add Demos") { Task { await library.addDemos() } }
            }.disabled(library.busy)
            List(library.filtered, selection: $librarySelection) { value in
                VStack(alignment: .leading, spacing: 4) {
                    Label(value.name, systemImage: "waveform").lineLimit(2)
                    Text(value.available ? "Saved instrument" : "Missing").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.vertical, 5).tag(value.id).help(value.url.path)
            }.listStyle(.plain).scrollContentBackground(.hidden).onChange(of: librarySelection) { _, _ in library.stopPreview() }
            Text(library.previewDescription ?? "\(library.filtered.count) instruments").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Button(library.previewing == nil ? "Preview" : "Stop Preview") {
                    if library.previewing != nil { library.stopPreview() }
                    else if let entry { ensemble.stop(); model.stop(); Task { await library.preview(entry) } }
                }.disabled(library.busy || ensemble.busy || model.busy || (library.previewing == nil && entry?.available != true))
                Button("Assign") { if let entry, let part { library.stopPreview(); Task { await ensemble.loadInstrument(entry.url, part: part.id) } } }
                    .disabled(!ensemble.canEdit || library.busy || entry?.available != true || part == nil)
            }
            Button("Add as Part") {
                guard let entry, let added = ensemble.addPart() else { return }
                select(added.id, added.primaryClipID)
                library.stopPreview(); Task { await ensemble.loadInstrument(entry.url, part: added.id) }
            }.disabled(!ensemble.canEdit || library.busy || entry?.available != true || ensemble.parts.count >= 4)
            if let entry {
                Button("Remove from List") { library.remove(entry); librarySelection = nil }.font(.system(size: 10)).disabled(library.busy)
            }
            Divider()
            Text("SAMPLE STUDIO").font(.system(size: 10)).tracking(1.2).foregroundStyle(.secondary)
            Button("Waveform & Instrument…") { openStudio() }.disabled(ensemble.busy || model.busy)
                .accessibilityLabel("Open Sample Studio")
            Text("WAV · Sampling · Keyboard · MIDI · AI").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(13).frame(maxHeight: .infinity).background(Color.white.opacity(0.025))
    }
    private var transport: some View {
        HStack(spacing: 20) {
            Button("Stop All") { ensemble.stop(); library.stopPreview(); model.stop() }.accessibilityLabel("Stop all workspace audio")
            Button(ensemble.playing ? "Stop" : "Play All") {
                if ensemble.playing { ensemble.stop() }
                else { model.stop(); library.stopPreview(); ensemble.play() }
            }.buttonStyle(StudioButton(primary: true)).disabled(ensemble.busy || ensemble.parts.isEmpty)
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: "%06.2f / %.2f", ensemble.positionBeats, arrangementBeats)).font(.system(size: 18, design: .monospaced))
                Text(ensemble.releasing ? "RELEASE TAILS" : "POSITION · BEATS").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 200, alignment: .leading)
            TextField("Ensemble tempo", value: $ensemble.tempo, format: .number).textFieldStyle(.roundedBorder).frame(width: 58).disabled(!ensemble.canEdit)
            Text("BPM").foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "MASTER · %.0f dB", ensemble.masterDB)).font(.system(size: 10))
                Slider(value: $ensemble.masterDB, in: -60...0).frame(width: 145).tint(accent).accessibilityLabel("Ensemble master volume").disabled(ensemble.busy)
                Text("Output \(Int(ensemble.level)) dB").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 20).padding(.vertical, 14).background(Color.white.opacity(0.025))
    }
    private var arrangementBeats: Double {
        max(EnsembleSections.end(ensemble.sections), ensemble.parts.flatMap(\.allClips).map {
            EnsembleSections.offset($0.sectionID, in: ensemble.sections) + ($0.startBeat.isFinite ? max(0, $0.startBeat) : 0)
                + (EnsembleTimeline.repeatedLength($0.performance, count: $0.repeatCount) ?? 0)
        }.max() ?? 0)
    }
    private func requestOpen() {
        guard ensemble.canEdit else { return }
        library.stopPreview()
        if ensemble.dirty { confirmOpen = true } else { ensemble.openPanel() }
    }
    private func select(_ partID: UUID, _ clipID: UUID) { selectedPart = partID; selectedClip = clipID }
    private func openStudio() { ensemble.stop(); library.stopPreview(); model.ensembleWorkspaceActive = false }
    private var currentInstrument: EnsembleInstrument? {
        guard let sample = model.instrumentSample else { return nil }
        return EnsembleInstrument(sample: sample, root: model.rootNote, envelope: model.envelope, loop: model.sampleLoop,
                                  name: model.instrumentFileURL?.deletingPathExtension().lastPathComponent ?? sample.name)
    }
}
