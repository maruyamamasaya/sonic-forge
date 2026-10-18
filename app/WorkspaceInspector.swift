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
            Picker("設定の種類", selection: $tab) { Text("演奏クリップ").tag("Clip"); Text("楽器").tag("Instrument") }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("パート名", text: $part.name).font(.system(size: 15, weight: .medium)).textFieldStyle(.plain).disabled(!ensemble.canEdit)
                    if tab == "Clip" { clipSettings } else { instrumentSettings }
                    Divider()
                    Text("パート音量・全クリップで共通").font(.system(size: 9)).foregroundStyle(.secondary)
                    Toggle("消音", isOn: $part.muted).disabled(ensemble.busy)
                    Slider(value: $part.gainDB, in: -36...0).accessibilityIdentifier("\(part.name) volume").accessibilityLabel("\(part.name) の音量").disabled(ensemble.busy)
                    Text(String(format: "%.0f dB・%d/8音・出力 %.0f dB", part.gainDB, part.voices, part.level)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Button("パート削除") { ensemble.remove(part.id) }.disabled(!ensemble.canEdit)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
            }
        }.padding(.horizontal, 16).padding(.bottom, 16).controlSize(.small)
            .onChange(of: clipID) { _, _ in tab = "Clip" }
    }
    private var clipSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(clip.performance.name).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("セクション", selection: binding(\.sectionID)) {
                Text("曲の先頭から").tag(Optional<UUID>.none)
                ForEach(ensemble.sections) { Text($0.name).tag(Optional($0.id)) }
            }.accessibilityIdentifier("Selected clip section").accessibilityLabel("選択クリップのセクション").help(StudioHelpTopic.section.explanation)
            HStack { Text("開始・拍"); Spacer(); TextField("クリップの開始拍", value: binding(\.startBeat), format: .number).frame(width: 66).textFieldStyle(.roundedBorder) }
            Stepper("繰り返し ×\(clip.repeatCount)", value: binding(\.repeatCount), in: 1...16).accessibilityIdentifier("Selected clip repeat").accessibilityLabel("クリップの繰り返し回数").help(StudioHelpTopic.beat.explanation)
            Divider()
            Text("演奏データ").font(.system(size: 10)).foregroundStyle(.secondary)
            Menu("プリセット") {
                ForEach(MIDIPerformancePreset.allCases) { preset in
                    Button(JapaneseUI.preset(preset)) { ensemble.setClipPerformance(.preset(preset), part: part.id, clip: clip.id) }
                }
            }
            HStack {
                Button("開く…") { ensemble.openClipPerformance(part: part.id, clip: clip.id) }
                Button("編集中の演奏を使う") { ensemble.setClipPerformance(currentPerformance, part: part.id, clip: clip.id) }
            }
            Stepper("移調 \(clip.performance.transpose) 半音", value: binding(\.performance.transpose), in: -24...24).accessibilityIdentifier("Selected clip transpose").accessibilityLabel("クリップ全体の移調")
            Stepper("強弱 \(Int(clip.performance.velocityPercent))%", value: binding(\.performance.velocityPercent), in: 25...150, step: 5).accessibilityIdentifier("Selected clip velocity").accessibilityLabel("クリップ全体の強弱").help(StudioHelpTopic.velocity.explanation)
            Text("\(clip.performance.notes.count) 音符・共通テンポ").font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            EnsembleDuplicateMenu(part: part, ensemble: ensemble, clip: clip)
            Menu("演奏クリップ追加") {
                ForEach(ensemble.sections) { section in Button(section.name) { ensemble.addClip(part: part.id, sectionID: section.id) } }
                Button("曲の先頭から") { ensemble.addClip(part: part.id, sectionID: nil) }
            }.disabled(part.additionalClips.count >= 7)
            if clip.id != part.primaryClipID { Button("クリップ削除") { ensemble.removeClip(part: part.id, clip: clip.id) } }
            Text("このクリップだけに適用。音色と音量はパート全体で共通です。").font(.system(size: 10)).foregroundStyle(.secondary)
        }.disabled(!ensemble.canEdit)
    }
    private var instrumentSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(part.instrument?.name ?? "左の一覧から楽器を割り当ててください").foregroundStyle(.secondary)
            Button("楽器を開く…") { ensemble.openInstrument(part.id) }
            if let instrument = part.instrument {
                Picker("基準音", selection: Binding(get: { instrument.root }, set: { update(root: $0) })) {
                    ForEach(48...72, id: \.self) { Text(NotePitch.name($0)).tag($0) }
                }.accessibilityIdentifier("Selected instrument root").accessibilityLabel("選択楽器の基準音").help(StudioHelpTopic.root.explanation)
                Text("\(Int(instrument.sample.buffer.format.sampleRate)) Hz · \(timeLabel(Double(instrument.sample.buffer.frameLength) / instrument.sample.buffer.format.sampleRate))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Divider()
                envelopeControl("Attack", path: \.attack, range: 0...5)
                envelopeControl("Decay", path: \.decay, range: 0...5)
                envelopeControl("Sustain", path: \.sustain, range: 0...1)
                envelopeControl("Release", path: \.release, range: 0...5)
                Divider()
                Toggle("素材をループ", isOn: loopBinding(\.enabled)).accessibilityIdentifier("Selected instrument loop").accessibilityLabel("選択楽器のループ").help(StudioHelpTopic.loop.explanation)
                HStack { Text("開始・秒"); Spacer(); TextField("ループ開始・秒", value: loopTimeBinding(\.startFrame), format: .number).frame(width: 85).textFieldStyle(.roundedBorder) }
                HStack { Text("終了・秒"); Spacer(); TextField("ループ終了・秒", value: loopTimeBinding(\.endFrame), format: .number).frame(width: 85).textFieldStyle(.roundedBorder) }
                HStack { Text("継ぎ目・ms"); Spacer(); TextField("継ぎ目のクロスフェード・ms", value: loopTimeBinding(\.crossfadeFrames, milliseconds: true), format: .number).frame(width: 70).textFieldStyle(.roundedBorder) }
                Text("このパートの全クリップに適用し、構成と保存します。楽器の元ファイルは保持します。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.disabled(!ensemble.canEdit)
    }
    private func envelopeControl(_ name: String, path: WritableKeyPath<ADSRParameters, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 3) {
            HStack { Text(JapaneseUI.envelopeName(name)); Spacer(); Text(String(format: name == "Sustain" ? "%.0f %%" : "%.3f s", (part.instrument?.envelope[keyPath: path] ?? 0) * (name == "Sustain" ? 100 : 1))).monospacedDigit() }
            Slider(value: Binding(get: { part.instrument?.envelope[keyPath: path] ?? 0 }, set: { value in
                guard var envelope = part.instrument?.envelope else { return }; envelope[keyPath: path] = value; update(envelope: envelope)
            }), in: range).accessibilityIdentifier("Selected instrument \(name)").accessibilityLabel("選択楽器の" + JapaneseUI.envelopeName(name)).help(JapaneseUI.envelopeHelp(name))
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
