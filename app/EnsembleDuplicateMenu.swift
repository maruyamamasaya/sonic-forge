import SwiftUI

struct EnsembleDuplicateMenu: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let clip: EnsembleClip
    var body: some View {
        Menu("別の区切りへ複製…") {
            ForEach(ensemble.sections.filter { $0.id != clip.sectionID }) { section in
                Button(section.name) { ensemble.duplicateClip(part: part.id, clip: clip.id, to: section.id) }
            }
            if clip.sectionID != nil {
                Button("曲の先頭から") { ensemble.duplicateClip(part: part.id, clip: clip.id, to: nil) }
            }
        }.frame(width: 115).disabled(!ensemble.canEdit || part.additionalClips.count >= 7 || ensemble.sections.isEmpty)
            .accessibilityIdentifier("Duplicate clip for \(part.name) \(clip.id)").accessibilityLabel("クリップを複製 \(part.name) \(clip.id)")
            .help("演奏・開始拍・繰り返しを別セクションへコピーします。元の演奏は残ります。")
    }
}
