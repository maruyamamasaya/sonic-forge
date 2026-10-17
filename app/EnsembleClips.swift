import Foundation

/// Additional performances share the part's instrument and mixer.
struct EnsembleClip: Codable, Identifiable, Equatable {
    var id = UUID()
    var performance: PerformanceDocument
    var startBeat = 0.0
    var repeatCount = 1
    var sectionID: UUID? = nil
}

enum EnsembleClips {
    static func validate(_ clips: [EnsembleClip], root: Int, sections: [EnsembleSection]) throws {
        guard (1...8).contains(clips.count), Set(clips.map(\.id)).count == clips.count else {
            throw AudioError.invalid("1パートの演奏クリップは1〜8個、IDは重複なしで指定してください。")
        }
        var ranges: [(Double, Double)] = []
        for clip in clips {
            guard clip.startBeat.isFinite, (0...256).contains(clip.startBeat), (1...16).contains(clip.repeatCount) else {
                throw AudioError.invalid("クリップの開始位置・繰り返し回数が無効です。")
            }
            _ = try clip.performance.events(root: root)
            let length = EnsembleTimeline.repeatedLength(clip.performance, count: clip.repeatCount)!
            try EnsembleSections.validatePlacement(sectionID: clip.sectionID, start: clip.startBeat, length: length, sections: sections)
            let start = EnsembleSections.offset(clip.sectionID, in: sections) + clip.startBeat
            ranges.append((start, start + length))
        }
        ranges.sort { $0.0 < $1.0 }
        for index in 1..<ranges.count where ranges[index].0 < ranges[index - 1].1 - 0.000001 {
            throw AudioError.invalid("同じ楽器パート内の演奏クリップが重なっています。開始位置やセクションを調整してください。")
        }
    }
    static func events(_ clips: [EnsembleClip], root: Int, tempo: Double, sections: [EnsembleSection]) throws -> [MIDIPerformanceEvent] {
        try validate(clips, root: root, sections: sections)
        // Earlier clip's final pedal-up/off precedes the next clip's first note at a shared boundary.
        let ordered = clips.sorted {
            EnsembleSections.offset($0.sectionID, in: sections) + $0.startBeat < EnsembleSections.offset($1.sectionID, in: sections) + $1.startBeat
        }
        return try ordered.flatMap { clip in
            try EnsembleTimeline.events(clip.performance, root: root, tempo: tempo,
                startBeat: EnsembleSections.offset(clip.sectionID, in: sections) + clip.startBeat, count: clip.repeatCount)
        }
    }
}
