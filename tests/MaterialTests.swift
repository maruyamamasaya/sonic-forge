import Foundation
import AVFoundation
import SQLite3

enum MaterialTests {
    @MainActor static func run() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("SonicForge-MaterialTests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let job = root.appendingPathComponent("job")
        try fm.createDirectory(at: job, withIntermediateDirectories: true)
        func audio(_ name: String, _ scale: Float) throws -> URL {
            let url = job.appendingPathComponent(name)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
            buffer.frameLength = 4410
            for c in 0..<2 { for f in 0..<4410 { buffer.floatChannelData![c][f] = Float(f + c) / 4410 * scale } }
            try file.write(from: buffer)
            return url
        }
        let input = try audio("input.wav", 0.2), stem = try audio("drums.wav", 0.4)
        let hash = try MaterialHash.file(input)
        let provenance = MaterialProvenance(sourceName: "テスト曲", inputSHA256: hash, runID: UUID().uuidString,
            model: "htdemucs", backend: "mlx-metal", settings: .standard, weightSHA256: SeparationClient.weightHash, versions: ["fixture": "1"], gain: 1,
            preprocessing: "demucs-mlx-load_audio-44100-stereo-outer-normalization-v1", stem: "drums", frames: 4410, sampleRate: 44100)
        var origin: MaterialOrigin? = MaterialOrigin(provenance: provenance, input: input, original: input, stem: stem, lease: SeparationLease(job))
        let libraryRoot = root.appendingPathComponent("library")
        let store = MaterialStore(root: libraryRoot)
        let range = AudioSelection(startFrame: 101, endFrame: 3210)
        let draft = try await store.prepare(origin: origin!, selection: range, name: "硬いドラム")
        precondition(draft.additionalBytes > 0)
        let before = try await store.list(); precondition(before.isEmpty)
        let first = try await store.commit(draft.id)
        let duplicateDraft = try await store.prepare(origin: origin!, selection: range, name: "再登録")
        precondition(duplicateDraft.additionalBytes == 0)
        let duplicate = try await store.commit(duplicateDraft.id)
        precondition(duplicate.id == first.id)
        let one = try await store.prepare(origin: origin!, selection: AudioSelection(startFrame: 4409, endFrame: 4410), name: "末尾1frame")
        let last = try await store.commit(one.id)
        precondition(last.selection.frameCount == 1)
        let cancelDraft = try await store.prepare(origin: origin!, selection: AudioSelection(startFrame: 0, endFrame: 20), name: "取消")
        await store.discard(cancelDraft.id)
        do { _ = try await store.commit(cancelDraft.id); fatalError("Discarded draft committed") } catch {}
        do {
            _ = try await store.prepare(origin: origin!, selection: AudioSelection(startFrame: -1, endFrame: 2), name: "不正")
            fatalError("Invalid range saved")
        } catch {}
        // A failed transaction must not expose a partial material or overwrite a run's settings.
        var changed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(provenance)) as! [String: Any]
        changed["gain"] = 0.5
        let conflict = try JSONDecoder().decode(MaterialProvenance.self, from: JSONSerialization.data(withJSONObject: changed))
        let conflictOrigin = MaterialOrigin(provenance: conflict, input: input, original: input, stem: stem, lease: nil)
        let rejected = try await store.prepare(origin: conflictOrigin, selection: AudioSelection(startFrame: 0, endFrame: 100), name: "不整合")
        do { _ = try await store.commit(rejected.id); fatalError("Run metadata overwritten") } catch {}
        let afterFailure = try await store.list(); precondition(afterFailure.count == 2)
        let tampered = try await store.prepare(origin: origin!, selection: AudioSelection(startFrame: 0, endFrame: 30), name: "破損準備")
        try Data("changed".utf8).write(to: libraryRoot.appendingPathComponent("staging/" + tampered.id.uuidString + "/clip.wav"))
        do { _ = try await store.commit(tampered.id); fatalError("Changed draft published") } catch {}
        // Adoption owns the provenance lease independently from the separation candidates.
        let adoption = PlayerModel(materialStore: store)
        let adopted = await adoption.useSeparatedAudio(stem, origin: origin!)
        precondition(adopted)
        adoption.separation.cleanup()
        origin = nil
        precondition(fm.fileExists(atPath: job.path))
        adoption.cleanup()
        precondition(!fm.fileExists(atPath: job.path))
        // All temporary job files disappear, even though the catalog remains usable.
        let restarted = MaterialStore(root: libraryRoot)
        let records = try await restarted.list(); precondition(records.count == 2)
        let restored = try await restarted.restore(first.id)
        precondition(restored.record == first && restored.record.selection == range && restored.record.provenance == provenance)
        let full = try AVAudioFile(forReading: restored.origin.stem), clip = try AVAudioFile(forReading: restored.clip)
        let a = AVAudioPCMBuffer(pcmFormat: full.processingFormat, frameCapacity: 3109)!
        let b = AVAudioPCMBuffer(pcmFormat: clip.processingFormat, frameCapacity: 3109)!
        full.framePosition = 101; try full.read(into: a); try clip.read(into: b)
        precondition(a.frameLength == 3109 && b.frameLength == 3109)
        for c in 0..<2 { for f in 0..<3109 { precondition(a.floatChannelData![c][f] == b.floatChannelData![c][f]) } }
        let tail = try await restarted.restore(last.id)
        let tailFile = try AVAudioFile(forReading: tail.clip)
        precondition(tailFile.length == 1)
        // New PlayerModel approximates process restart: no venv, job, or source path is required.
        let player = PlayerModel(materialStore: restarted)
        let opened = await player.openMaterial(first.id)
        precondition(opened && player.editor.selection == range && player.materialOrigin?.provenance == provenance)
        precondition(player.position == Double(range.startFrame) / 44100)
        if CommandLine.arguments.contains("--playback") {
            await player.playSelection()
            precondition(player.playingSelection && player.playing)
            player.stop()
            precondition(!player.playing && player.editor.selection == range)
        }
        // A second cut uses absolute parent frames, not the previous clip's start twice.
        player.select(from: 200.0 / 4410, to: 500.0 / 4410)
        precondition(player.editor.selection == AudioSelection(startFrame: 200, endFrame: 500))
        let recut = try await restarted.prepare(origin: player.materialOrigin!, selection: player.editor.selection!, name: "再切り出し")
        let cut = try await restarted.commit(recut.id)
        precondition(cut.startFrame == 200 && cut.endFrame == 500)
        let originalOpened = await player.openMaterial(first.id, original: true)
        precondition(originalOpened && player.editor.selection == range && player.materialOrigin == nil && player.restoredMaterial == first)
        // Failed restoration preserves the currently loaded waveform and range.
        let previousURL = player.asset!.url
        try Data("broken".utf8).write(to: restored.clip)
        let failed = await player.openMaterial(first.id)
        precondition(!failed && player.asset?.url == previousURL && player.editor.selection == range)
        player.cleanup()
        let cancelled = Task {
            try Task.checkCancellation()
            return try await restarted.prepare(origin: restored.origin, selection: range, name: "取消")
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled save succeeded") } catch is CancellationError {} catch { throw error }
        // Unknown schemas and corrupt catalogs are refused without resetting user data.
        let futureRoot = root.appendingPathComponent("future")
        try fm.createDirectory(at: futureRoot, withIntermediateDirectories: true)
        var db: OpaquePointer?
        sqlite3_open(futureRoot.appendingPathComponent("catalog.sqlite").path, &db)
        sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil); sqlite3_close(db)
        let futureData = try Data(contentsOf: futureRoot.appendingPathComponent("catalog.sqlite"))
        do { _ = try await MaterialStore(root: futureRoot).list(); fatalError("Future schema accepted") } catch {}
        let futureAfter = try Data(contentsOf: futureRoot.appendingPathComponent("catalog.sqlite"))
        precondition(futureAfter == futureData)
        let corruptRoot = root.appendingPathComponent("corrupt")
        try fm.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corrupt = corruptRoot.appendingPathComponent("catalog.sqlite")
        try Data("invalid catalog".utf8).write(to: corrupt)
        do { _ = try await MaterialStore(root: corruptRoot).list(); fatalError("Corrupt schema accepted") } catch {}
        let corruptAfter = try Data(contentsOf: corrupt)
        precondition(corruptAfter == Data("invalid catalog".utf8))
        print("PASS: material SQLite persistence/restart, exact source-frame/PCM restoration, dedup, one-frame/recut, discard/cancel, missing/corrupt audio preservation and schema protection")
    }
}
