import SwiftUI

struct WorkspaceInspector: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let currentPerformance: PerformanceDocument
    let clipID: UUID
    @State private var tab = "Clip"
    private var clip: EnsembleClip { part.allClips.first { $0.id == clipID } ?? part.allClips[0] }
    private func binding<Value>(_ path: WritableKeyPath<EnsembleClip, Value>) -> Binding<Value> {
        Binding(get: { clip[keyPath: path] }, set: { value in ensemble.editClip(part: part.id, clip: clip.id) { $0[keyPath: path] = value } })
    }
    var body: some View {
        VStack(spacing: 12) {
            Picker("Inspector mode", selection: $tab) { Text("Clip").tag("Clip"); Text("Instrument").tag("Instrument") }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Part name", text: $part.name).font(.system(size: 15, weight: .medium)).textFieldStyle(.plain).disabled(!ensemble.canEdit)
                    if tab == "Clip" { clipSettings } else { instrumentSettings }
                    Divider()
                    Text("PART MIX · Shared by all clips").font(.system(size: 9)).foregroundStyle(.secondary)
                    Toggle("Mute", isOn: $part.muted).disabled(ensemble.busy)
                    Slider(value: $part.gainDB, in: -36...0).accessibilityLabel("\(part.name) volume").disabled(ensemble.busy)
                    Text(String(format: "%.0f dB · %d/8 voices · Output %.0f dB", part.gainDB, part.voices, part.level)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Button("Remove Part") { ensemble.remove(part.id) }.disabled(!ensemble.canEdit)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
            }
        }.padding(.horizontal, 16).padding(.bottom, 16).controlSize(.small)
            .onChange(of: clipID) { _, _ in tab = "Clip" }
    }
    private var clipSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(clip.performance.name).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("Section", selection: binding(\.sectionID)) {
                Text("Song · absolute").tag(Optional<UUID>.none)
                ForEach(ensemble.sections) { Text($0.name).tag(Optional($0.id)) }
            }.accessibilityLabel("Selected clip section")
            HStack { Text("Start / beats"); Spacer(); TextField("Selected clip start", value: binding(\.startBeat), format: .number).frame(width: 66).textFieldStyle(.roundedBorder) }
            Stepper("Repeat ×\(clip.repeatCount)", value: binding(\.repeatCount), in: 1...16).accessibilityLabel("Selected clip repeat")
            Divider()
            Text("PERFORMANCE").font(.system(size: 10)).foregroundStyle(.secondary)
            Menu("Preset") {
                ForEach(MIDIPerformancePreset.allCases) { preset in
                    Button(preset.rawValue) { ensemble.setClipPerformance(.preset(preset), part: part.id, clip: clip.id) }
                }
            }
            HStack {
                Button("Open…") { ensemble.openClipPerformance(part: part.id, clip: clip.id) }
                Button("Use Current") { ensemble.setClipPerformance(currentPerformance, part: part.id, clip: clip.id) }
            }
            Stepper("Pitch \(clip.performance.transpose) st", value: binding(\.performance.transpose), in: -24...24).accessibilityLabel("Selected clip transpose")
            Stepper("Velocity \(Int(clip.performance.velocityPercent))%", value: binding(\.performance.velocityPercent), in: 25...150, step: 5).accessibilityLabel("Selected clip velocity")
            Text("\(clip.performance.notes.count) notes · Shared tempo").font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            EnsembleDuplicateMenu(part: part, ensemble: ensemble, clip: clip)
            Menu("Add Section Clip") {
                ForEach(ensemble.sections) { section in Button(section.name) { ensemble.addClip(part: part.id, sectionID: section.id) } }
                Button("Song · absolute") { ensemble.addClip(part: part.id, sectionID: nil) }
            }.disabled(part.additionalClips.count >= 7)
            if clip.id != part.primaryClipID { Button("Remove Clip") { ensemble.removeClip(part: part.id, clip: clip.id) } }
            Text("This clip only. Instrument and mix are shared by the part.").font(.system(size: 10)).foregroundStyle(.secondary)
        }.disabled(!ensemble.canEdit)
    }
    private var instrumentSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(part.instrument?.name ?? "Assign an instrument from the library").foregroundStyle(.secondary)
            Button("Open Instrument…") { ensemble.openInstrument(part.id) }
            if let instrument = part.instrument {
                Picker("Root", selection: Binding(get: { instrument.root }, set: { update(root: $0) })) {
                    ForEach(48...72, id: \.self) { Text(NotePitch.name($0)).tag($0) }
                }.accessibilityLabel("Selected instrument root")
                Text("\(Int(instrument.sample.buffer.format.sampleRate)) Hz · \(timeLabel(Double(instrument.sample.buffer.frameLength) / instrument.sample.buffer.format.sampleRate))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                envelopeControl("Attack", path: \.attack, range: 0...5)
                envelopeControl("Decay", path: \.decay, range: 0...5)
                envelopeControl("Sustain", path: \.sustain, range: 0...1)
                envelopeControl("Release", path: \.release, range: 0...5)
                Divider()
                Toggle("Sample Loop", isOn: loopBinding(\.enabled)).accessibilityLabel("Selected instrument loop")
                HStack { Text("Start / seconds"); Spacer(); TextField("Loop start seconds", value: loopTimeBinding(\.startFrame), format: .number).frame(width: 85).textFieldStyle(.roundedBorder) }
                HStack { Text("End / seconds"); Spacer(); TextField("Loop end seconds", value: loopTimeBinding(\.endFrame), format: .number).frame(width: 85).textFieldStyle(.roundedBorder) }
                HStack { Text("Crossfade / ms"); Spacer(); TextField("Loop crossfade milliseconds", value: loopTimeBinding(\.crossfadeFrames, milliseconds: true), format: .number).frame(width: 70).textFieldStyle(.roundedBorder) }
                Text("Applied to every clip in this part. Saved with the ensemble; the library file is kept.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.disabled(!ensemble.canEdit)
    }
    private func envelopeControl(_ name: String, path: WritableKeyPath<ADSRParameters, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(String(format: name == "Sustain" ? "%.0f %%" : "%.3f s", (part.instrument?.envelope[keyPath: path] ?? 0) * (name == "Sustain" ? 100 : 1))).monospacedDigit() }
            Slider(value: Binding(get: { part.instrument?.envelope[keyPath: path] ?? 0 }, set: { value in
                guard var envelope = part.instrument?.envelope else { return }; envelope[keyPath: path] = value; update(envelope: envelope)
            }), in: range).accessibilityLabel("Selected instrument \(name)")
        }.font(.system(size: 11))
    }
    private func loopBinding<Value>(_ path: WritableKeyPath<SampleLoop, Value>) -> Binding<Value> {
        let fallback = part.instrument!.loop[keyPath: path]
        return Binding(get: { part.instrument?.loop[keyPath: path] ?? fallback }, set: { value in
            guard var loop = part.instrument?.loop else { return }; loop[keyPath: path] = value; update(loop: loop)
        })
    }
    private func loopTimeBinding(_ path: WritableKeyPath<SampleLoop, Int64>, milliseconds: Bool = false) -> Binding<Double> {
        Binding(get: {
            guard let instrument = part.instrument else { return 0 }
            return Double(instrument.loop[keyPath: path]) / instrument.sample.buffer.format.sampleRate * (milliseconds ? 1000 : 1)
        }, set: { value in
            guard let instrument = part.instrument else { return }
            let frames = value / (milliseconds ? 1000 : 1) * instrument.sample.buffer.format.sampleRate
            guard frames.isFinite, frames >= 0, frames <= Double(instrument.sample.buffer.frameLength) else {
                ensemble.error = "ループ位置・クロスフェードの範囲を確認してください。"; return
            }
            var loop = instrument.loop; loop[keyPath: path] = Int64(frames.rounded()); update(loop: loop)
        })
    }
    private func update(root: Int? = nil, envelope: ADSRParameters? = nil, loop: SampleLoop? = nil) {
        guard let old = part.instrument else { return }
        ensemble.setInstrumentSettings(part: part.id, root: root ?? old.root, envelope: envelope ?? old.envelope, loop: loop ?? old.loop)
    }
}
