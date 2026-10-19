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
                    EnsemblePanControl(part: part, ensemble: ensemble)
                    Divider()
                    EnsembleEQControl(part: part, ensemble: ensemble)
                    Divider()
                    EnsembleReverbControl(part: part, ensemble: ensemble)
                    Divider()
                    EnsembleCompressorControl(part: part, ensemble: ensemble)
                    Divider()
                    EnsembleDelayControl(part: part, ensemble: ensemble)
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
                    ForEach(NotePitch.rootRange, id: \.self) { Text(NotePitch.name($0)).tag($0) }
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

struct EnsemblePanControl: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    private var position: String {
        if abs(part.pan) < 0.005 { return "中央" }
        return String(format: "%@ %.0f%%", part.pan < 0 ? "左" : "右", abs(part.pan) * 100)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("パン・左右の配置").foregroundStyle(.secondary)
                Spacer()
                Text(position).monospacedDigit()
                Button("中央") { part.pan = 0 }.accessibilityIdentifier("Center pan for \(part.id)")
                    .accessibilityLabel("\(part.name) のパンを中央に戻す")
            }
            HStack(spacing: 7) {
                Text("左")
                Slider(value: $part.pan, in: -1...1).accessibilityIdentifier("Pan for \(part.id)")
                    .accessibilityLabel("\(part.name) のパン・左右の配置")
                    .accessibilityValue(position)
                Text("右")
            }
        }.font(.system(size: 10)).disabled(ensemble.busy)
            .help("パート全体の音を左右へ配置します。中央0・左−1・右+1。同じ楽器の全クリップで共通。再生中も調整でき、構成保存とWAVに反映します。")
    }
}

struct EnsembleEQControl: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("EQ・音質").foregroundStyle(.secondary)
                Spacer()
                Button("フラット") { part.eq = .flat }.accessibilityIdentifier("Reset EQ for \(part.id)")
                    .accessibilityLabel("\(part.name) のEQをフラットに戻す")
            }
            band("低音", key: "low", path: \.lowDB, detail: "200 Hz以下を中心に、音の太さを調整します。")
            band("中音", key: "mid", path: \.midDB, detail: "1 kHz付近の存在感を調整します。")
            band("高音", key: "high", path: \.highDB, detail: "4 kHz以上を中心に、明るさを調整します。")
            Text("±12 dB・全クリップで共通").font(.system(size: 9)).foregroundStyle(.secondary)
        }.font(.system(size: 10)).disabled(ensemble.busy)
            .help("低音・中音・高音の音量を調整します。0 dBが元の音。フラットですべて0に戻します。上げると音量も増えるため、パート音量も調整してください。")
    }
    private func band(_ name: String, key: String, path: WritableKeyPath<PartEQ, Double>, detail: String) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(String(format: "%+.1f dB", part.eq[keyPath: path])).monospacedDigit() }
            Slider(value: Binding(get: { part.eq[keyPath: path] }, set: { value in
                var eq = part.eq; eq[keyPath: path] = value; part.eq = eq
            }), in: -12...12, step: 0.5)
                .accessibilityIdentifier("EQ \(key) for \(part.id)").accessibilityLabel("\(part.name) のEQ・\(name)")
                .help(detail + " −12〜+12 dB、0.5 dB刻み。")
        }
    }
}

struct EnsembleReverbControl: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("リバーブ・響き").foregroundStyle(.secondary)
                Spacer()
                Button("オフ") { part.reverb = 0 }
                    .accessibilityIdentifier("Reset reverb for \(part.id)")
                    .accessibilityLabel("\(part.name) のリバーブをオフにする")
            }
            Slider(value: $part.reverb, in: 0...100, step: 1)
                .accessibilityIdentifier("Reverb for \(part.id)")
                .accessibilityLabel("\(part.name) のリバーブ・響きの量")
            Text(part.reverb == 0 ? "オフ・小さな部屋" : String(format: "響き %.0f%%・小さな部屋", part.reverb))
                .monospacedDigit().foregroundStyle(.secondary)
        }.font(.system(size: 10)).disabled(ensemble.busy)
            .help("小さな部屋の響きを加えます。0%でオフ、100%で響きだけになります。同じパートの全クリップで共通。再生・構成保存・WAVに反映し、余韻は最大3秒まで残します。全停止で余韻も止まります。")
    }
}

struct EnsembleDelayControl: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ディレイ・繰り返す音").foregroundStyle(.secondary)
                Spacer()
                Button("オフ") { var value = part.delay; value.mix = 0; part.delay = value }
                    .accessibilityIdentifier("Reset delay for \(part.id)")
                    .accessibilityLabel("\(part.name) のディレイをオフにする")
            }
            band("間隔", key: "time", path: \.timeMS, range: 50...1000, step: 10, unit: "ms")
            band("量", key: "mix", path: \.mix, range: 0...100, step: 1, unit: "%")
            band("繰り返し", key: "feedback", path: \.feedback, range: 0...60, step: 1, unit: "%")
            Text(part.delay.mix == 0 ? "オフ・全クリップで共通" : "全クリップで共通・テンポ同期なし")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.font(.system(size: 10)).disabled(ensemble.busy)
            .help("音を遅らせて繰り返します。間隔は50〜1000 ms、量0%でオフ・100%で遅れた音だけ。繰り返しは戻す音の割合で0〜60%。拍やクリップの開始位置とは別の設定です。再生・保存・余韻込みのWAVに反映し、全停止で止まります。")
    }
    private func band(_ name: String, key: String, path: WritableKeyPath<PartDelay, Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(String(format: "%.0f", part.delay[keyPath: path]) + " " + unit).monospacedDigit() }
            Slider(value: Binding(get: { part.delay[keyPath: path] }, set: { value in
                var settings = part.delay; settings[keyPath: path] = value; part.delay = settings
            }), in: range, step: step)
                .accessibilityIdentifier("Delay \(key) for \(part.id)")
                .accessibilityLabel("\(part.name) のディレイ・\(name)")
        }
    }
}

struct EnsembleCompressorControl: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("コンプレッサー・音量を整える", isOn: Binding(get: { part.compressor.enabled }, set: { value in
                var settings = part.compressor; settings.enabled = value; part.compressor = settings
            }))
                .accessibilityIdentifier("Compressor enabled for \(part.id)")
                .accessibilityLabel("\(part.name) のコンプレッサーを有効にする")
                .help("大きな音を抑えて強弱の差を整えます。EQの後、ディレイ・リバーブの前に作用。再生・構成保存・WAVに反映します。オフで圧縮と補正音量をバイパス。自動音量合わせではありません。")
            band("しきい値", key: "threshold", path: \.thresholdDB, range: -40...0, step: 1, unit: "dB")
                .help("このレベルを超える大きな音を抑えます。値を下げるほど多くの音に作用します。")
            band("ヘッドルーム", key: "headroom", path: \.headroomDB, range: 0.1...40, step: 0.1, unit: "dB")
                .help("小さい値ほど強く圧縮します。固定の比率（レシオ）ではありません。")
            band("アタック", key: "attack", path: \.attackMS, range: 0.1...200, step: 0.1, unit: "ms")
                .help("大きな音を抑え始める速さ。短いほど立ち上がりも抑えます。")
            band("リリース", key: "release", path: \.releaseMS, range: 10...3000, step: 10, unit: "ms")
                .help("圧縮を解除する速さ。楽器のADSRの余韻とは別です。")
            band("補正音量", key: "makeup", path: \.makeupDB, range: 0...24, step: 1, unit: "dB")
                .help("圧縮で小さくなった音量を補います。上げすぎた場合はパート音量を下げてください。")
            Text(part.compressor.enabled ? "オン・全クリップで共通" : "オフ・設定を保持")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.font(.system(size: 10)).disabled(ensemble.busy)
    }
    private func band(_ name: String, key: String, path: WritableKeyPath<PartCompressor, Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(spacing: 3) {
            HStack { Text(name); Spacer(); Text(String(format: "%.1f", part.compressor[keyPath: path]) + " " + unit).monospacedDigit() }
            Slider(value: Binding(get: { part.compressor[keyPath: path] }, set: { value in
                var settings = part.compressor; settings[keyPath: path] = value; part.compressor = settings
            }), in: range, step: step)
                .accessibilityIdentifier("Compressor \(key) for \(part.id)")
                .accessibilityLabel("\(part.name) のコンプレッサー・\(name)")
        }
    }
}
