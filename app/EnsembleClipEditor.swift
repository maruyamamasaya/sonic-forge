import SwiftUI

struct EnsembleClipEditor: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let clip: EnsembleClip
    let currentPerformance: PerformanceDocument
    private func binding<Value>(_ path: WritableKeyPath<EnsembleClip, Value>) -> Binding<Value> {
        Binding(get: { (part.additionalClips.first { $0.id == clip.id } ?? clip)[keyPath: path] }, set: { value in
            ensemble.editClip(part: part.id, clip: clip.id) { $0[keyPath: path] = value }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Section for clip \(clip.id) in \(part.name)", selection: binding(\.sectionID)) {
                    Text("曲の先頭から").tag(Optional<UUID>.none)
                    ForEach(ensemble.sections) { section in Text(section.name).tag(Optional(section.id)) }
                }.labelsHidden().frame(width: 150)
                Text(clip.performance.name).font(.system(size: 11)).lineLimit(1)
                Spacer()
                Menu("プリセット") {
                    ForEach(MIDIPerformancePreset.allCases) { preset in
                        Button(JapaneseUI.preset(preset)) { ensemble.setClipPerformance(.preset(preset), part: part.id, clip: clip.id) }
                    }
                }.frame(width: 65)
                Button("開く…") { ensemble.openClipPerformance(part: part.id, clip: clip.id) }
                Button("編集中の演奏を使う") { ensemble.setClipPerformance(currentPerformance, part: part.id, clip: clip.id) }
                Button("クリップ削除") { ensemble.removeClip(part: part.id, clip: clip.id) }
            }
            HStack {
                Text("開始")
                TextField("クリップ開始拍", value: binding(\.startBeat), format: .number).frame(width: 48).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("Clip start for \(part.name) \(clip.id)").accessibilityLabel("クリップ開始拍 \(part.name) \(clip.id)")
                Stepper("", value: binding(\.startBeat), in: 0...256, step: 0.25).labelsHidden()
                Text("拍・繰り返し")
                Stepper(value: binding(\.repeatCount), in: 1...16) { Text("×\(clip.repeatCount)").monospacedDigit() }
                    .frame(width: 70).accessibilityIdentifier("Clip repeat for \(part.name) \(clip.id)").accessibilityLabel("クリップ繰り返し \(part.name) \(clip.id)")
                Spacer()
                Text("\(clip.performance.notes.count) 音符・Shared instrument & mix").foregroundStyle(.secondary)
            }.font(.system(size: 10))
            HStack(spacing: 12) {
                Text("演奏の変化").foregroundStyle(.secondary)
                Stepper(value: Binding(get: { clip.performance.transpose }, set: { value in
                    ensemble.editClip(part: part.id, clip: clip.id) { $0.performance.transpose = value }
                }), in: -24...24) { Text("Pitch \(clip.performance.transpose > 0 ? "+" : "")\(clip.performance.transpose) st").monospacedDigit() }
                    .frame(width: 135).accessibilityIdentifier("Clip transpose for \(part.name) \(clip.id)").accessibilityLabel("クリップ移調 \(part.name) \(clip.id)")
                Stepper(value: Binding(get: { clip.performance.velocityPercent }, set: { value in
                    ensemble.editClip(part: part.id, clip: clip.id) { $0.performance.velocityPercent = value }
                }), in: 25...150, step: 5) { Text("強弱 \(Int(clip.performance.velocityPercent))%").monospacedDigit() }
                    .frame(width: 155).accessibilityIdentifier("Clip velocity for \(part.name) \(clip.id)").accessibilityLabel("クリップ強弱 \(part.name) \(clip.id)")
                Spacer()
                EnsembleDuplicateMenu(part: part, ensemble: ensemble, clip: clip)
            }.font(.system(size: 10))
        }.padding(10).background(Color.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 4))
            .disabled(!ensemble.canEdit)
    }
}
