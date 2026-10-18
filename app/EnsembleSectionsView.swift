import SwiftUI

struct EnsembleSectionsView: View {
    @ObservedObject var ensemble: EnsembleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("曲のセクション").font(.system(size: 10, weight: .medium)).tracking(1.5)
                Text("左から順に再生・開始拍は各セクション内の位置")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Button("セクション追加") { ensemble.addSection() }.disabled(ensemble.sections.count >= 8)
                Button("デモ曲") { Task { await ensemble.addSharedSongDemo() } }
                    .disabled(!ensemble.parts.isEmpty || !ensemble.sections.isEmpty)
            }
            if !ensemble.sections.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach($ensemble.sections) { $section in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    TextField("セクション名", text: $section.name).font(.system(size: 11, weight: .medium))
                                        .accessibilityIdentifier("Section name \(section.id)").accessibilityLabel("セクション名 \(section.id)")
                                    Button { ensemble.duplicateSection(section.id) } label: { Image(systemName: "plus.square.on.square") }
                                        .accessibilityIdentifier("Duplicate section \(section.name) \(section.id)").accessibilityLabel("セクションを複製 \(section.name) \(section.id)")
                                        .help("このセクションと中の全演奏を、すぐ後ろへまとめて複製します。")
                                        .disabled(ensemble.sections.count >= 8)
                                }
                                HStack(spacing: 5) {
                                    TextField("拍", value: $section.beats, format: .number).frame(width: 42)
                                        .accessibilityIdentifier("Section length for \(section.name)").accessibilityLabel("セクションの長さ \(section.name)")
                                    Text("拍").foregroundStyle(.secondary)
                                    Button { ensemble.reorderSection(section.id, by: -1) } label: { Image(systemName: "chevron.left") }
                                        .accessibilityIdentifier("Move section earlier \(section.name)").accessibilityLabel("セクションを前へ \(section.name)")
                                    Button { ensemble.reorderSection(section.id, by: 1) } label: { Image(systemName: "chevron.right") }
                                        .accessibilityIdentifier("Move section later \(section.name)").accessibilityLabel("セクションを後へ \(section.name)")
                                    Button { ensemble.removeSection(section.id) } label: { Image(systemName: "xmark") }
                                        .accessibilityIdentifier("Remove section \(section.name)").accessibilityLabel("セクションを削除 \(section.name)")
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
