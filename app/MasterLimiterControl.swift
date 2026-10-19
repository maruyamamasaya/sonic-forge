import SwiftUI

struct MasterLimiterControl: View {
    @ObservedObject var ensemble: EnsembleModel
    @State private var showing = false
    var body: some View {
        Button(ensemble.limiter.enabled ? String(format: "リミッター %.1f dB", ensemble.limiter.ceilingDB) : "リミッター オフ") { showing = true }
            .font(.system(size: 10)).accessibilityIdentifier("Master limiter settings")
            .help("曲全体のピークを抑える設定を開きます。再生・構成保存・WAVに反映します。")
            .disabled(ensemble.busy)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("マスターリミッター").font(.headline)
                        Spacer()
                        Button("閉じる") { showing = false }.accessibilityIdentifier("Close master limiter settings")
                    }
                    Toggle("曲全体の音割れを抑える", isOn: Binding(get: { ensemble.limiter.enabled }, set: { value in
                        var settings = ensemble.limiter; settings.enabled = value; ensemble.limiter = settings
                    })).accessibilityIdentifier("Master limiter enabled")
                    Text("出力上限 \(ensemble.limiter.ceilingDB, specifier: "%.1f") dBFS").monospacedDigit()
                    Slider(value: Binding(get: { ensemble.limiter.ceilingDB }, set: { value in
                        var settings = ensemble.limiter; settings.ceilingDB = value; ensemble.limiter = settings
                    }), in: -12 ... -0.1, step: 0.1)
                        .accessibilityIdentifier("Master limiter ceiling").accessibilityLabel("リミッターの出力上限")
                        .help("大きすぎる音を抑える上限です。下げるほど余裕が増えます。0 dBFS未満に制限します。")
                    Text("リリース \(ensemble.limiter.releaseMS, specifier: "%.0f") ms").monospacedDigit()
                    Slider(value: Binding(get: { ensemble.limiter.releaseMS }, set: { value in
                        var settings = ensemble.limiter; settings.releaseMS = value; ensemble.limiter = settings
                    }), in: 1...60, step: 1)
                        .accessibilityIdentifier("Master limiter release").accessibilityLabel("リミッターのリリース")
                        .help("ピークを抑えた後に音量が戻る速さ。長いほどゆっくり戻ります。")
                    Text("全パートと全体音量の後に作用。オフでも設定を保持します。元音源の音割れは修復しません。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("リミッターデモを追加") { Task { await ensemble.addDemos(limited: true) } }
                        .disabled(!ensemble.canEdit || ensemble.parts.count > 2)
                        .accessibilityIdentifier("Add master limiter demo")
                        .help("音量を持ち上げた2パートとリミッターを追加します。曲全体の取り消しで追加前へ戻せます。")
                }.padding(18).frame(width: 300).font(.system(size: 11)).disabled(ensemble.busy)
            }
    }
}
