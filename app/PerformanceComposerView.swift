import SwiftUI

struct PerformanceComposerView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var midi: MIDIInput
    @ObservedObject var composer: PerformanceComposer
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReplace = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(accent)
                Text("Compose Performance").font(.system(size: 22, weight: .medium))
                Spacer()
                Button("Done") { composer.cancel(); dismiss() }.buttonStyle(StudioButton())
            }
            HStack {
                Picker("Generator", selection: $composer.provider) {
                    ForEach(PerformanceComposer.Provider.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 245).disabled(composer.generating)
                Spacer()
                Text("4 bars · \(NotePitch.name(model.rootNote)) · Up to 8 voices").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Group {
                switch composer.provider {
                case .codex:
                    HStack {
                        TextField("Codex executable", text: $composer.executable).textFieldStyle(.roundedBorder)
                        Button("Choose…") { composer.browseCodex() }
                    }
                    Text("Uses your Codex CLI login. Instructions and root note are sent through Codex; no audio is attached.")
                case .openai:
                    HStack {
                        SecureField("OpenAI API key · session only", text: $composer.apiKey).textFieldStyle(.roundedBorder)
                        TextField("Model", text: $composer.model).textFieldStyle(.roundedBorder).frame(width: 170)
                    }
                    Text("Sends instructions and root note to OpenAI. API usage is billed separately. Key stays in memory until quit.")
                case .external:
                    HStack {
                        Text("Copy the brief into another AI, then paste its performance JSON below.")
                        Spacer()
                        Button("Copy Brief") { composer.copyBrief(root: model.rootNote) }
                    }
                case .demo:
                    Text("Offline demo · Two programmed examples, not AI generation. Try calm chords or a bouncy phrase.")
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary).disabled(composer.generating)
            Text("DESCRIBE YOUR PERFORMANCE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            TextEditor(text: $composer.prompt).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 75).background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel("Performance instruction").disabled(composer.generating)
            HStack {
                Button("落ち着いた和音") { composer.prompt = "落ち着いた和音。ゆっくり、柔らかい強弱で。" }
                Button("少し跳ねたフレーズ") { composer.prompt = "少し跳ねたフレーズ。軽いスウィングと強弱をつけて。" }
                Spacer()
                if composer.generating {
                    ProgressView().controlSize(.small)
                    Button("Cancel Generation") { composer.cancel() }
                } else {
                    Button(composer.provider == .external ? "Validate JSON" : composer.provider == .demo ? "Generate Demo" : "Generate") {
                        composer.generate(root: model.rootNote)
                    }.buttonStyle(StudioButton(primary: true)).disabled(model.instrumentSample == nil || model.busy)
                }
            }.controlSize(.small)
            if composer.provider == .external {
                TextEditor(text: $composer.externalJSON).font(.system(size: 10, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).frame(height: 110).background(.black.opacity(0.2)).accessibilityLabel("Generated performance JSON")
                    .disabled(composer.generating)
            } else if let candidate = composer.candidate {
                PerformanceRoll(document: candidate, accent: accent).frame(height: 130)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: composer.generating ? "waveform" : "pianokeys").font(.system(size: 24)).foregroundStyle(accent)
                    Text(composer.generating ? "Creating your performance…" : "Describe a mood, rhythm, or phrase")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 130).background(.black.opacity(0.12))
            }
            if let candidate = composer.candidate {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        Text("\(composer.source ?? "") · \(candidate.notes.count) notes · \(Int(candidate.tempo)) BPM · Validated")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use & Play") {
                        if midi.performanceDirty { confirmReplace = true } else { useCandidate() }
                    }.buttonStyle(StudioButton(primary: true)).disabled(model.busy || midi.performing)
                }
            }
            if let error = composer.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3).help(error) }
            Spacer(minLength: 0)
            Text("Review the result, then Use & Play. Adjust or save it with Edit… afterward. Your instrument stays unchanged.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 780, height: 640)
            .background(Color(red: 0.075, green: 0.09, blue: 0.105)).preferredColorScheme(.dark)
            .onDisappear { composer.cancel() }
            .confirmationDialog("Replace unsaved performance?", isPresented: $confirmReplace) {
                Button("Replace & Play", role: .destructive) { useCandidate() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Cancel and save the current performance with Edit… → Save… if you want to keep it.") }
    }
    private func useCandidate() {
        guard let candidate = composer.candidate, composer.candidateRoot == model.rootNote else {
            composer.error = "楽器の基準音が変わりました。もう一度生成してください。"; return
        }
        guard midi.applyGeneratedPerformance(candidate, root: model.rootNote) else { composer.error = midi.error; return }
        onUse()
        dismiss()
    }
}

private struct PerformanceRoll: View {
    let document: PerformanceDocument
    let accent: Color
    var body: some View {
        Canvas { context, size in
            let low = (document.notes.map(\.pitch).min() ?? 48) - 2
            let high = (document.notes.map(\.pitch).max() ?? 72) + 2
            for beat in 0...16 {
                var path = Path(); let x = size.width * Double(beat) / 16
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(beat % 4 == 0 ? 0.15 : 0.05)), lineWidth: 1)
            }
            for note in document.notes {
                let row = size.height / Double(high - low + 1)
                let rect = CGRect(x: size.width * note.beat / 16, y: Double(high - note.pitch) * row,
                                  width: max(2, size.width * note.duration / 16 - 1), height: max(2, row - 1))
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(accent.opacity(0.3 + Double(note.velocity) / 180)))
            }
        }.background(.black.opacity(0.2)).accessibilityLabel("Generated performance piano roll, \(document.notes.count) notes across four bars")
    }
}
