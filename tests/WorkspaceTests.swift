import Foundation

enum WorkspaceTests {
    @MainActor static func run() async throws {
        let model = EnsembleModel(); await model.addSharedSongDemo()
        let part = model.parts[0], other = model.parts[1]
        let primary = part.allClips[0], extra = part.additionalClips
        model.editClip(part: part.id, clip: part.primaryClipID) {
            $0.performance.transpose = 1; $0.performance.velocityPercent = 85; $0.startBeat = 0.25
        }
        precondition(part.performance.transpose == 1 && part.startBeat == 0.25 && part.additionalClips == extra)
        let edited = part.allClips
        model.editClip(part: part.id, clip: UUID()) { $0.performance.transpose = 9 }
        precondition(part.allClips == edited)
        let original = part.instrument!, otherInstrument = other.instrument!
        let adsr = ADSRParameters(attack: 0.12, decay: 0.2, sustain: 0.4, release: 0.7)
        model.setInstrumentSettings(part: part.id, root: 58, envelope: adsr, loop: original.loop)
        precondition(part.instrument!.root == 58 && part.instrument!.envelope == adsr && part.instrument!.sample.buffer === original.sample.buffer)
        precondition(other.instrument!.root == otherInstrument.root && other.instrument!.envelope == otherInstrument.envelope)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("workspace.sfensemble")
        let saved = await model.save(to: file, remember: false); precondition(saved && !model.dirty)
        var badLoop = original.loop; badLoop.endFrame = 0
        model.setInstrumentSettings(part: part.id, root: 58, envelope: adsr, loop: badLoop)
        precondition(!model.dirty && part.instrument!.loop == original.loop && model.error != nil)
        let restored = EnsembleModel(); let loaded = await restored.load(file, remember: false)
        precondition(loaded && restored.parts[0].performance == part.performance && restored.parts[0].startBeat == 0.25 && restored.parts[0].instrument!.root == 58 && restored.parts[0].instrument!.envelope == adsr)
        precondition(part.primaryClipID == primary.id)
        if CommandLine.arguments.contains("--playback") {
            restored.play(); try await Task.sleep(nanoseconds: 150_000_000)
            let before = restored.parts[0].performance
            restored.editClip(part: restored.parts[0].id, clip: restored.parts[0].primaryClipID) { $0.performance.transpose = 3 }
            restored.setInstrumentSettings(part: restored.parts[0].id, root: 60, envelope: adsr, loop: original.loop)
            precondition(restored.parts[0].performance == before && restored.parts[0].instrument!.root == 58)
            restored.stop(); precondition(restored.parts.allSatisfy { $0.voices == 0 })
        }
        print("PASS: selected primary clip editing, shared instrument settings, independent parts, invalid-loop preservation, v5 restoration and playback edit lock")
    }
}
