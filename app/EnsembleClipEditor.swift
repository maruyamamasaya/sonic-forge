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
                    Text("Song · absolute").tag(Optional<UUID>.none)
                    ForEach(ensemble.sections) { section in Text(section.name).tag(Optional(section.id)) }
                }.labelsHidden().frame(width: 150)
                Text(clip.performance.name).font(.system(size: 11)).lineLimit(1)
                Spacer()
                Menu("Preset") {
                    ForEach(MIDIPerformancePreset.allCases) { preset in
                        Button(preset.rawValue) { ensemble.setClipPerformance(.preset(preset), part: part.id, clip: clip.id) }
                    }
                }.frame(width: 65)
                Button("Open…") { ensemble.openClipPerformance(part: part.id, clip: clip.id) }
                Button("Use Current") { ensemble.setClipPerformance(currentPerformance, part: part.id, clip: clip.id) }
                Button("Remove Clip") { ensemble.removeClip(part: part.id, clip: clip.id) }
            }
            HStack {
                Text("START")
                TextField("Clip start", value: binding(\.startBeat), format: .number).frame(width: 48).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Clip start for \(part.name) \(clip.id)")
                Stepper("", value: binding(\.startBeat), in: 0...256, step: 0.25).labelsHidden()
                Text("beats · REPEAT")
                Stepper(value: binding(\.repeatCount), in: 1...16) { Text("×\(clip.repeatCount)").monospacedDigit() }
                    .frame(width: 70).accessibilityLabel("Clip repeat for \(part.name) \(clip.id)")
                Spacer()
                Text("\(clip.performance.notes.count) notes · Shared instrument & mix").foregroundStyle(.secondary)
            }.font(.system(size: 10))
        }.padding(10).background(Color.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 4))
            .disabled(!ensemble.canEdit)
    }
}
