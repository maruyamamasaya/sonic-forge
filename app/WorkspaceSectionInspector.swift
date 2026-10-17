import SwiftUI

struct WorkspaceSectionInspector: View {
    @ObservedObject var ensemble: EnsembleModel
    let sectionID: UUID
    let onSelect: (UUID?) -> Void
    private var section: EnsembleSection? { ensemble.sections.first { $0.id == sectionID } }
    private func binding<Value>(_ path: WritableKeyPath<EnsembleSection, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { section?[keyPath: path] ?? fallback }, set: { value in
            guard ensemble.canEdit, let index = ensemble.sections.firstIndex(where: { $0.id == sectionID }) else { return }
            ensemble.sections[index][keyPath: path] = value
        })
    }
    var body: some View {
        ScrollView {
            if section != nil {
                VStack(alignment: .leading, spacing: 16) {
                    Text("SECTION").font(.system(size: 10)).tracking(1.2).foregroundStyle(.secondary)
                    TextField("Section name", text: binding(\.name, fallback: "")).font(.system(size: 16, weight: .medium)).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Selected section name")
                    Divider()
                    HStack {
                        Text("Start / beats").foregroundStyle(.secondary)
                        Spacer()
                        Text(EnsembleSections.offset(sectionID, in: ensemble.sections), format: .number.precision(.fractionLength(0...2))).monospacedDigit()
                    }
                    HStack {
                        Text("Length / beats").foregroundStyle(.secondary)
                        Spacer()
                        TextField("Selected section length", value: binding(\.beats, fallback: 16), format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                    }
                    Text("\(ensemble.parts.flatMap(\.allClips).filter { $0.sectionID == sectionID }.count) clips · Follows section order").font(.system(size: 11)).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Button { ensemble.reorderSection(sectionID, by: -1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Move selected section earlier")
                            .disabled(ensemble.sections.first?.id == sectionID)
                        Button { ensemble.reorderSection(sectionID, by: 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Move selected section later")
                            .disabled(ensemble.sections.last?.id == sectionID)
                        Button("Duplicate") { if let id = ensemble.duplicateSection(sectionID) { onSelect(id) } }
                            .disabled(ensemble.sections.count >= 8).accessibilityLabel("Duplicate selected section")
                    }
                    Button("Remove Section") {
                        ensemble.removeSection(sectionID)
                        if !ensemble.sections.contains(where: { $0.id == sectionID }) { onSelect(nil) }
                    }
                    Text("Copies include every assigned part’s clips. Instrument and mix stay shared.").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Assigned clips must be moved before removing a section.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.disabled(!ensemble.canEdit)
    }
}
