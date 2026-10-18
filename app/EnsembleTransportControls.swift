import SwiftUI

/// Session-local audition controls shared by the main workspace and all-parts sheet.
struct EnsembleTransportControls: View {
    @ObservedObject var ensemble: EnsembleModel
    var selectedSection: UUID? = nil
    @State private var seekBeat = 0.0
    @State private var start = 0.0
    @State private var end = 4.0
    var body: some View {
        HStack(spacing: 8) {
            Text("開始位置").foregroundStyle(.secondary)
            TextField("再生開始拍", value: $seekBeat, format: .number).frame(width: 58)
                .accessibilityIdentifier("Song seek beat").help("曲頭を0とした拍数。移動を押すか、タイムラインの拍目盛りをクリックします。")
            Button("移動") { ensemble.seek(to: seekBeat) }.accessibilityIdentifier("Seek song")
                .disabled(!seekBeat.isFinite || seekBeat < 0 || seekBeat > ensemble.arrangementLength)
            Divider().frame(height: 16)
            Toggle("範囲ループ", isOn: Binding(get: { ensemble.rangeLoopEnabled }, set: { ensemble.setRangeLoopEnabled($0) }))
                .toggleStyle(.checkbox).accessibilityIdentifier("Song range loop")
                .help("指定範囲だけを繰り返し試聴します。クリップの繰り返し回数やWAV出力は変えません。")
            TextField("範囲開始拍", value: $start, format: .number).frame(width: 55).accessibilityIdentifier("Song loop start")
            Text("–").foregroundStyle(.secondary)
            TextField("範囲終了拍", value: $end, format: .number).frame(width: 55).accessibilityIdentifier("Song loop end")
            Text("拍").foregroundStyle(.secondary)
            Button("範囲を適用") { _ = ensemble.setPlaybackRange(start: start, end: end) }.accessibilityIdentifier("Apply song loop range")
                .help("¼拍以上の範囲を設定してループを有効にします。終了の拍は次の周回に含みません。")
            if let selectedSection {
                Button("選択区切り") { ensemble.loopSection(selectedSection) }.accessibilityIdentifier("Loop selected section")
                    .help("選択中のイントロ・サビなどを再生範囲にします。")
            }
            Spacer(minLength: 0)
            Text(ensemble.rangeLoopEnabled ? "範囲を保持して一時停止 → 編集 → 再生" : "目盛りクリックで再生位置を指定")
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.font(.system(size: 10)).textFieldStyle(.roundedBorder).disabled(!ensemble.canEdit)
            .onAppear { syncRange(); seekBeat = ensemble.positionBeats }
            .onChange(of: ensemble.playbackRange) { _, _ in syncRange() }
            .onChange(of: ensemble.arrangementLength) { _, _ in if ensemble.playbackRange == nil { syncRange() } }
            .onChange(of: ensemble.playing) { _, playing in if !playing { seekBeat = ensemble.positionBeats } }
            .onChange(of: ensemble.positionBeats) { _, position in if !ensemble.playing { seekBeat = position } }
    }
    private func syncRange() {
        start = ensemble.playbackRange?.lowerBound ?? 0
        end = ensemble.playbackRange?.upperBound ?? min(4, ensemble.arrangementLength)
    }
}
