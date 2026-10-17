import SwiftUI

struct EnsembleDuplicateMenu: View {
    @ObservedObject var part: EnsemblePart
    @ObservedObject var ensemble: EnsembleModel
    let clip: EnsembleClip
    var body: some View {
        Menu("Duplicate To…") {
            ForEach(ensemble.sections.filter { $0.id != clip.sectionID }) { section in
                Button(section.name) { ensemble.duplicateClip(part: part.id, clip: clip.id, to: section.id) }
            }
            if clip.sectionID != nil {
                Button("Song · absolute") { ensemble.duplicateClip(part: part.id, clip: clip.id, to: nil) }
            }
        }.frame(width: 115).disabled(!ensemble.canEdit || part.additionalClips.count >= 7 || ensemble.sections.isEmpty)
            .accessibilityLabel("Duplicate clip for \(part.name) \(clip.id)")
            .help("Copy this performance, START and REPEAT to another section. The source remains unchanged.")
    }
}
