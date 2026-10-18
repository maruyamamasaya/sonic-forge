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
                    Text("セクション").font(.system(size: 10)).tracking(1.2).foregroundStyle(.secondary)
                    TextField("セクション名", text: binding(\.name, fallback: "")).font(.system(size: 16, weight: .medium)).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("Selected section name").accessibilityLabel("選択セクションの名前")
                    Divider()
                    HStack {
                        Text("開始・拍").foregroundStyle(.secondary)
                        Spacer()
                        Text(EnsembleSections.offset(sectionID, in: ensemble.sections), format: .number.precision(.fractionLength(0...2))).monospacedDigit()
                    }
                    HStack {
                        Text("長さ・拍").foregroundStyle(.secondary)
                        Spacer()
                        TextField("セクションの長さ・拍", value: binding(\.beats, fallback: 16), format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                    }
                    Text("\(ensemble.parts.flatMap(\.allClips).filter { $0.sectionID == sectionID }.count) クリップ・セクションの順に再生").font(.system(size: 11)).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Button { ensemble.reorderSection(sectionID, by: -1) } label: { Image(systemName: "chevron.left") }.accessibilityIdentifier("Move selected section earlier").accessibilityLabel("セクションを前へ")
                            .disabled(ensemble.sections.first?.id == sectionID)
                        Button { ensemble.reorderSection(sectionID, by: 1) } label: { Image(systemName: "chevron.right") }.accessibilityIdentifier("Move selected section later").accessibilityLabel("セクションを後へ")
                            .disabled(ensemble.sections.last?.id == sectionID)
                        Button("複製") { if let id = ensemble.duplicateSection(sectionID) { onSelect(id) } }
                            .disabled(ensemble.sections.count >= 8).accessibilityIdentifier("Duplicate selected section").accessibilityLabel("セクションをまとめて複製")
                    }
                    Button("セクション削除") {
                        ensemble.removeSection(sectionID)
                        if !ensemble.sections.contains(where: { $0.id == sectionID }) { onSelect(nil) }
                    }
                    Text("中の全パートの演奏もまとめて複製します。音色と音量は共通です。").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("削除する前に、この区切り内のクリップを移動してください。").font(.system(size: 11)).foregroundStyle(.secondary)
                }.font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.disabled(!ensemble.canEdit)
    }
}
