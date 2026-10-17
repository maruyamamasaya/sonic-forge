import Foundation

struct EnsembleSection: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var beats: Double
}

enum EnsembleSections {
    static func validate(_ sections: [EnsembleSection]) throws {
        guard sections.count <= 8, Set(sections.map(\.id)).count == sections.count,
              sections.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 && $0.beats.isFinite && (1...256).contains($0.beats) }) else {
            throw AudioError.invalid("セクションは最大8個、名前1〜40文字、長さ1〜256拍で指定してください。")
        }
    }
    static func offset(_ id: UUID?, in sections: [EnsembleSection]) -> Double {
        guard let id, let index = sections.firstIndex(where: { $0.id == id }) else { return 0 }
        return sections[..<index].reduce(0) { $0 + ($1.beats.isFinite ? max(0, min(256, $1.beats)) : 0) }
    }
    static func end(_ sections: [EnsembleSection]) -> Double {
        sections.reduce(0) { $0 + ($1.beats.isFinite ? max(0, min(256, $1.beats)) : 0) }
    }
    static func validatePlacement(sectionID: UUID?, start: Double, length: Double?, sections: [EnsembleSection]) throws {
        guard let sectionID else { return }
        guard let section = sections.first(where: { $0.id == sectionID }) else { throw AudioError.invalid("パートのセクションが見つかりません。") }
        guard start.isFinite, start >= 0, let length, start + length <= section.beats + 0.000001 else {
            throw AudioError.invalid("演奏がセクションの長さを超えています。START・REPEATを減らすかセクションを長くしてください。")
        }
    }
}
