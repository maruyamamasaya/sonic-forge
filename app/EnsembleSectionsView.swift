import SwiftUI

struct EnsembleSectionsView: View {
    @ObservedObject var ensemble: EnsembleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SONG SECTIONS").font(.system(size: 10, weight: .medium)).tracking(1.5)
                Text("Ordered left to right · START is relative to the assigned section")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button("Add Section") { ensemble.addSection() }.disabled(ensemble.sections.count >= 8)
                Button("Demo Song") { Task { await ensemble.addSongDemo() } }
                    .disabled(!ensemble.parts.isEmpty || !ensemble.sections.isEmpty)
            }
            if !ensemble.sections.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach($ensemble.sections) { $section in
                            VStack(alignment: .leading, spacing: 5) {
                                TextField("Section name", text: $section.name).font(.system(size: 11, weight: .medium))
                                    .accessibilityLabel("Section name \(section.id)")
                                HStack(spacing: 5) {
                                    TextField("Beats", value: $section.beats, format: .number).frame(width: 42)
                                        .accessibilityLabel("Section length for \(section.name)")
                                    Text("beats").foregroundStyle(.secondary)
                                    Button { ensemble.reorderSection(section.id, by: -1) } label: { Image(systemName: "chevron.left") }
                                        .accessibilityLabel("Move section earlier \(section.name)")
                                    Button { ensemble.reorderSection(section.id, by: 1) } label: { Image(systemName: "chevron.right") }
                                        .accessibilityLabel("Move section later \(section.name)")
                                    Button { ensemble.removeSection(section.id) } label: { Image(systemName: "xmark") }
                                        .accessibilityLabel("Remove section \(section.name)")
                                }.font(.system(size: 10))
                            }.textFieldStyle(.plain).padding(9).frame(width: 230)
                                .background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }.buttonStyle(StudioButton()).controlSize(.small).disabled(!ensemble.canEdit)
    }
}
