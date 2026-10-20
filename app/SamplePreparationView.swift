import SwiftUI

struct SamplePreparationView: View {
    let source: InstrumentSample
    let apply: (InstrumentSample) -> Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var processing = SamplePreparationModel()
    @State private var settings = SamplePreparationSettings()
    private let amber = Color(red: 0.96, green: 0.72, blue: 0.33)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("サンプルを整える").font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }.accessibilityIdentifier("samplePreparation.close")
            }
            Text("現在の楽器サンプルの音量と端を整えます。採用した音は楽器に保存され、曲の再生や書き出しにも使えます。")
                .font(.caption).foregroundStyle(.secondary)
            Text(source.name).font(.caption).lineLimit(1)
            Text("波形表示と「選択範囲のWAV書き出し」は元素材です。この加工は鍵盤で鳴らす楽器サンプルに適用します。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("音量を合わせる", isOn: $settings.normalize)
                .accessibilityIdentifier("samplePreparation.normalize")
                .help("左右共通の倍率でピークを揃えます。大きくする量は最大24 dBです。")
            control("目標ピーク", value: $settings.targetDB, range: -12 ... -0.1, unit: "dBFS", id: "target")
                .disabled(!settings.normalize)
            control("フェードイン", value: $settings.fadeInMS, range: 0 ... 250, unit: "ms", id: "fadeIn")
            control("フェードアウト", value: $settings.fadeOutMS, range: 0 ... 250, unit: "ms", id: "fadeOut")
            Text("フェードはクリック音を減らすための短い音量変化です。強いアタックを残したい場合はフェードインを短くしてください。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("加工を準備") { processing.prepare(source, settings: settings) }
                    .disabled(processing.busy).accessibilityIdentifier("samplePreparation.prepare")
                if processing.busy {
                    ProgressView().controlSize(.small)
                    Text("準備中…").font(.caption)
                    Button("中止") { processing.cancel() }.accessibilityIdentifier("samplePreparation.cancel")
                }
            }
            if let result = processing.result {
                HStack {
                    Text("ピーク \(peak(result.report.originalPeak)) → \(peak(result.report.resultPeak))")
                    Spacer()
                    Text(String(format: "音量補正 %+.1f dB", result.report.gainDB))
                }.font(.caption).monospacedDigit().accessibilityIdentifier("samplePreparation.result")
                if result.report.boostLimited {
                    Text("小さな音を増幅しすぎないよう、補正を24 dBに抑えました。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("加工前を聴く") { processing.preview(.original) }
                        .accessibilityIdentifier("samplePreparation.previewOriginal")
                    Button("加工後を聴く") { processing.preview(.prepared) }
                        .accessibilityIdentifier("samplePreparation.previewProcessed")
                    Button("停止") { processing.stop() }.disabled(processing.audition == nil)
                        .accessibilityIdentifier("samplePreparation.stop")
                    Spacer()
                    Button("この音を採用") {
                        processing.stop()
                        if apply(result.sample) { dismiss() }
                    }.buttonStyle(.borderedProminent).tint(amber)
                        .accessibilityIdentifier("samplePreparation.apply")
                }
                Text("試聴は共通の−12 dBで再生します。採用後は「加工を戻す」で直前の音に戻せます。元のWAVは保持します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = processing.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(22).frame(width: 570).preferredColorScheme(.dark)
        .background { ZStack { WoodSurface(wood: .walnut); Color.black.opacity(0.65) } }
        .onChange(of: settings) { _, _ in processing.cancel() }
        .task { processing.prepare(source, settings: settings) }
        .onDisappear { processing.cancel() }
    }
    private func peak(_ value: Float) -> String {
        value > 0 ? String(format: "%.1f dBFS", 20 * log10(Double(value))) : "無音"
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, id: String) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range).tint(amber).accessibilityIdentifier("samplePreparation." + id)
            Text(String(format: "%.1f %@", value.wrappedValue, unit)).monospacedDigit().frame(width: 90, alignment: .trailing)
        }.font(.caption)
    }
}
