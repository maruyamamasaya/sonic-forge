import SwiftUI

struct ArrangementComposerView: View {
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var connection: PerformanceComposer
    @ObservedObject var composer: ArrangementComposer
    let wood: WorkspaceWood
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReplace = false
    private let accent = Color(red: 0.94, green: 0.81, blue: 0.55)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Arrange Ensemble").font(.custom("Georgia", size: 23))
                    Text("Shape the song with your existing instruments").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { composer.cancel(); dismiss() }
            }.padding(18).foregroundStyle(wood.ink).environment(\.colorScheme, wood.scheme)
                .background(WoodSurface(wood: wood, horizontalGrain: true))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Generator", selection: $connection.provider) {
                            ForEach(PerformanceComposer.Provider.allCases) { Text($0.rawValue).tag($0) }
                        }.frame(width: 245).disabled(composer.generating)
                        Spacer()
                        Text("\(ensemble.parts.count) instruments · Up to 8 sections").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    connectionSettings
                    TextEditor(text: $composer.prompt).font(.system(size: 14)).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 62).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Arrangement instruction").disabled(composer.generating)
                    HStack {
                        Button("薄いイントロ → 厚いサビ") { composer.prompt = "イントロは薄く、Aメロで動きを加えて、サビで厚く。" }
                        Button("均一な構成") { composer.prompt = "全パートを各セクションで使う均一な構成。" }
                        Spacer()
                        if composer.generating {
                            ProgressView().controlSize(.small)
                            Button("Cancel Generation") { composer.cancel() }
                        } else {
                            Button(connection.provider == .external ? "Validate JSON" : connection.provider == .demo ? "Generate Demo" : "Generate") {
                                composer.generate(ensemble: ensemble, connection: connection)
                            }.buttonStyle(CabinetButton(primary: true)).disabled(!ensemble.canEdit || ensemble.parts.isEmpty)
                        }
                    }
                    if connection.provider == .external {
                        TextEditor(text: $composer.externalJSON).font(.system(size: 10, design: .monospaced)).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 80).background(.black.opacity(0.2))
                            .accessibilityLabel("Generated arrangement JSON").disabled(composer.generating)
                    }
                    if let proposal = composer.candidate, let snapshot = composer.preview, let brief = composer.brief {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(proposal.name).font(.system(size: 17, weight: .medium))
                                Text("\(composer.source ?? "") · Validated · \(Int(proposal.tempo)) BPM · \(proposal.sections.reduce(0) { $0 + $1.beats }.formatted()) beats")
                                    .font(.system(size: 11)).foregroundStyle(accent)
                            }
                            Spacer()
                            Text("\(brief.snapshot.sections.count) → \(proposal.sections.count) sections\n\(brief.snapshot.parts.reduce(0) { $0 + $1.allClips.count }) → \(proposal.parts.reduce(0) { $0 + $1.clips.count }) clips")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(proposal.summary).font(.system(size: 12)).textSelection(.enabled)
                        ArrangementPreview(snapshot: snapshot).frame(height: 250)
                        Text("Clip bars show repeated key-down notes; pedal sustain and Release tails are heard during playback.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(accent)
                            Text(composer.generating ? "Creating an arrangement proposal…" : "Describe how the song should build")
                            Text("Review the sections, entries, notes and mix before adopting.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).frame(height: 210).background(.black.opacity(0.14))
                    }
                    if let error = composer.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(18)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adoption replaces all sections, clips, tempo and part mix.")
                    Text("Instruments and Master stay. Save the current ensemble first to keep a separate version.").foregroundStyle(.secondary)
                }.font(.system(size: 10))
                Spacer()
                Button("Save Current…") { ensemble.savePanel() }.disabled(!ensemble.canEdit || composer.generating)
                Button("Use Arrangement") {
                    if ensemble.dirty { confirmReplace = true } else { adopt() }
                }.buttonStyle(CabinetButton(primary: true))
                    .disabled(composer.candidate == nil || composer.generating || !ensemble.canEdit)
            }.padding(14)
        }.frame(width: 920, height: 690).background(Color(red: 0.10, green: 0.12, blue: 0.095))
            .buttonStyle(CabinetButton()).preferredColorScheme(.dark)
            .onChange(of: connection.provider) { _, _ in composer.cancel() }
            .onChange(of: connection.model) { _, _ in composer.cancel() }
            .onChange(of: connection.executable) { _, _ in composer.cancel() }
            .onDisappear { composer.cancel() }
            .confirmationDialog("Replace unsaved ensemble changes?", isPresented: $confirmReplace) {
                Button("Replace with Arrangement", role: .destructive) { adopt() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This replaces the complete section/clip layout, tempo and part mix, and clears note undo history. Cancel and use Save Current… to keep the original first.") }
    }
    @ViewBuilder private var connectionSettings: some View {
        Group {
            switch connection.provider {
            case .codex:
                HStack {
                    TextField("Codex executable", text: $connection.executable).textFieldStyle(.roundedBorder)
                    Button("Choose…") { connection.browseCodex() }
                }
                Text("Codex CLI login · CLI default model. Sends instructions, part names/roots, notes and layout; no audio or source paths.")
            case .openai:
                HStack {
                    SecureField("OpenAI API key · session only", text: $connection.apiKey).textFieldStyle(.roundedBorder)
                    TextField("Model", text: $connection.model).textFieldStyle(.roundedBorder).frame(width: 180)
                }
                Text("Sends instructions, part names/roots, notes and layout to OpenAI; no audio or source paths. API usage is billed separately.")
            case .external:
                HStack {
                    Text("Copy the context and schema to another AI, then paste its arrangement JSON.")
                    Spacer()
                    Button("Copy Brief") { composer.copyBrief(ensemble: ensemble) }
                }
            case .demo:
                Text("Offline demo · Programmed thin-intro/full-chorus or even arrangement. No AI is called.")
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary).disabled(composer.generating)
    }
    private func adopt() {
        if composer.adopt(ensemble: ensemble) { dismiss() }
    }
}

private struct ArrangementPreview: View {
    let snapshot: EnsembleSnapshot
    private func width(_ section: EnsembleSection) -> Double { max(110, section.beats * 12) }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text("PROPOSED SONG").font(.system(size: 10)).frame(width: 135)
                    ForEach(snapshot.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.name).font(.system(size: 12, weight: .semibold))
                            Text("\(section.beats.formatted()) beats").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(width: width(section), height: 42).background(.white.opacity(0.08))
                    }
                }
                ForEach(snapshot.parts.indices, id: \.self) { index in
                    let part = snapshot.parts[index]
                    HStack(spacing: 2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(part.name).lineLimit(2)
                            Text("\(part.gainDB.formatted()) dB · \(part.muted ? "Muted" : "On")").foregroundStyle(.secondary)
                        }.font(.system(size: 11)).frame(width: 125, alignment: .leading).padding(.horizontal, 5)
                        ForEach(snapshot.sections) { section in
                            GeometryReader { geometry in
                                ForEach(part.allClips.filter { $0.sectionID == section.id }) { clip in
                                    let length = EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount) ?? 0
                                    VStack(spacing: 1) {
                                        Text("\(clip.performance.notes.count) notes ×\(clip.repeatCount) @\(clip.startBeat.formatted())")
                                            .font(.system(size: 9)).lineLimit(1)
                                        PerformanceNoteView(performance: clip.performance, repeatCount: clip.repeatCount, root: part.instrument.root)
                                    }.padding(3).frame(width: max(2, length / section.beats * geometry.size.width), height: 53)
                                        .background(Color(red: 0.31, green: 0.35, blue: 0.23).opacity(part.muted ? 0.35 : 0.9))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .offset(x: clip.startBeat / section.beats * geometry.size.width, y: 3)
                                        .help("\(clip.performance.name) · \(clip.performance.notes.count) notes · \(clip.repeatCount) repeats · local beat \(clip.startBeat.formatted())")
                                }
                            }.frame(width: width(section), height: 60).background(.black.opacity(0.2))
                        }
                    }.accessibilityElement(children: .combine)
                        .accessibilityLabel("Proposed part \(part.name), \(part.allClips.count) clips, \(part.gainDB.formatted()) decibels, \(part.muted ? "muted" : "on")")
                }
            }.padding(6)
        }.background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Proposed arrangement timeline")
    }
}
