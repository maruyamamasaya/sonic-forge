import Foundation
import AVFoundation

// Offline fixtures only: Full never calls an external AI.
enum ArrangementGenerationTests {
    @MainActor static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-ArrangementTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = EnsembleModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await model.addSharedSongDemo()
        model.tempo = 240
        let saved = directory.appendingPathComponent("original.sfensemble")
        let initialSaved = await model.save(to: saved, remember: false); precondition(initialSaved)
        let originalFile = try Data(contentsOf: saved), originalSections = model.sections
        let ids = model.parts.map(\.id), originalNotes = model.parts.map(\.performance)
        let buffers = model.parts.map { $0.instrument!.sample.buffer }
        let brief = try model.arrangementBrief(prompt: "イントロは薄く、サビで厚く")
        let proposal = try ArrangementGeneration.demo(brief)
        let even = try ArrangementGeneration.demo(model.arrangementBrief(prompt: "均一な構成"))
        precondition(proposal.parts[1].clips.count == 2 && even.parts[1].clips.count == 3)
        let preview = try ArrangementGeneration.materialize(proposal, brief: brief)
        precondition(preview.sections.count == 3 && preview.parts.count == 2 && preview.masterDB == model.masterDB)
        precondition(preview.parts[0].performance.notes.count == 1 && preview.parts[0].additionalClips.last!.performance.notes.count == 3)
        precondition(model.sections == originalSections && model.parts.map(\.performance) == originalNotes && !model.dirty)
        let encoded = try JSONEncoder().encode(proposal)
        let decoded = try ArrangementGeneration.decode(encoded, brief: brief); precondition(decoded == proposal)
        let instructions = try brief.instructions
        precondition(instructions.contains(ids[0].uuidString) && !instructions.contains("SonicForge-ArrangementTest-") && !instructions.contains("base64"))
        func reject(_ value: ArrangementProposal) throws {
            let data = try JSONEncoder().encode(value)
            do { _ = try ArrangementGeneration.decode(data, brief: brief); fatalError("Invalid arrangement accepted") } catch {}
            precondition(!model.applyArrangement(value, brief: brief))
            precondition(model.sections == originalSections && model.parts.map(\.performance) == originalNotes && !model.dirty)
        }
        var bad = proposal; bad.parts[1].partID = bad.parts[0].partID; try reject(bad)
        bad = proposal; bad.parts[0].partID = UUID(); try reject(bad)
        bad = proposal; bad.parts.removeLast(); try reject(bad)
        bad = proposal; bad.parts[0].clips = []; try reject(bad)
        bad = proposal; bad.parts[0].clips = Array(repeating: bad.parts[0].clips[0], count: 9); try reject(bad)
        bad = proposal; bad.sections[0].beats = 65; try reject(bad)
        bad = proposal; bad.sections = Array(repeating: .init(name: "Long", beats: 64), count: 5); try reject(bad)
        bad = proposal; bad.parts[0].clips[0].sectionIndex = -1; try reject(bad)
        bad = proposal; bad.parts[0].clips[0].startBeat = 7; try reject(bad)
        bad = proposal; bad.parts[0].clips[0].repeatCount = 17; try reject(bad)
        bad = proposal; bad.parts[0].clips.append(bad.parts[0].clips[0]); try reject(bad)
        bad = proposal; bad.parts[0].gainDB = 1; try reject(bad)
        bad = proposal; bad.tempo = 20; try reject(bad)
        bad = proposal; bad.version = 2; try reject(bad)
        bad = proposal; bad.parts[0].clips[0].performance.notes[0].pitch = 110; try reject(bad)
        bad = proposal; bad.parts[0].clips[0].performance.notes[0].duration = 17; try reject(bad)
        bad = proposal; bad.parts[0].clips[0].performance.notes.append(bad.parts[0].clips[0].performance.notes[0]); try reject(bad)
        bad = proposal; bad.parts[0].clips[0].performance.pedals = [.init(beat: 0, down: true)]; try reject(bad)
        for data in [Data("bad".utf8), Data(repeating: 32, count: PerformanceGeneration.byteLimit + 1)] {
            do { _ = try ArrangementGeneration.decode(data, brief: brief); fatalError("Bad JSON accepted") } catch {}
        }
        // Existing HTTP and CLI boundaries are shared with phrase generation.
        let request = try OpenAIPerformanceClient.jsonRequest(instructions: instructions,
            schema: ArrangementGeneration.schema, name: "sonicforge_arrangement", key: "fixture-key", model: "fixture-model", maxTokens: 16000)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["store"] as? Bool == false && body["max_output_tokens"] as? Int == 16000)
        let format = (body["text"] as! [String: Any])["format"] as! [String: Any]
        precondition(format["name"] as? String == "sonicforge_arrangement" && format["strict"] as? Bool == true)
        let responseData = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": String(decoding: encoded, as: UTF8.self)]]]]])
        let client = OpenAIPerformanceClient(transport: { _ in
            (responseData, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let httpData = try await client.generateJSON(request)
        let httpProposal = try ArrangementGeneration.decode(httpData, brief: brief); precondition(httpProposal == proposal)
        let fixture = directory.appendingPathComponent("fixture.json"), executable = directory.appendingPathComponent("fake-codex")
        try encoded.write(to: fixture)
        try """
        #!/bin/sh
        set -eu
        output=''
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '--output-last-message' ]; then output="$2"; shift; fi
            shift
        done
        cat >/dev/null
        cp '\(fixture.path)' "$output"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let cliData = try await CodexPerformanceClient().generateJSON(instructions: instructions,
            schema: ArrangementGeneration.schema, executable: executable.path)
        let cliProposal = try ArrangementGeneration.decode(cliData, brief: brief); precondition(cliProposal == proposal)
        let composer = ArrangementComposer(), connection = PerformanceComposer()
        connection.provider = .demo
        composer.generate(ensemble: model, connection: connection)
        while composer.generating { await Task.yield() }
        precondition(composer.candidate != nil && composer.preview != nil && composer.source == "Demo" && !model.dirty)
        composer.generate(ensemble: model, connection: connection, override: { brief in
            try? await Task.sleep(nanoseconds: 80_000_000)
            return try ArrangementGeneration.demo(brief)
        })
        await Task.yield(); composer.cancel()
        try await Task.sleep(nanoseconds: 120_000_000)
        precondition(composer.candidate == nil && !composer.generating && !model.dirty)
        // A response arriving after an edit must not even be offered as a current proposal.
        composer.generate(ensemble: model, connection: connection, override: { brief in
            try await Task.sleep(nanoseconds: 50_000_000)
            return try ArrangementGeneration.demo(brief)
        })
        model.parts[0].gainDB = -3
        while composer.generating { await Task.yield() }
        precondition(composer.candidate == nil && composer.error != nil)
        precondition(!model.applyArrangement(proposal, brief: brief))
        precondition(model.parts.map(\.performance) == originalNotes && model.sections == originalSections)
        connection.provider = .external
        let fresh = try model.arrangementBrief(prompt: "イントロは薄く、サビで厚く")
        let freshProposal = try ArrangementGeneration.demo(fresh)
        composer.externalJSON = String(decoding: try JSONEncoder().encode(freshProposal), as: UTF8.self)
        composer.generate(ensemble: model, connection: connection)
        while composer.generating { await Task.yield() }
        precondition(composer.candidate == freshProposal && composer.source == "Other AI")
        precondition(composer.adopt(ensemble: model) && model.dirty && composer.candidate == nil)
        precondition(model.parts.map(\.id) == ids && model.sections.count == 3 && model.fileURL == saved)
        for (part, buffer) in zip(model.parts, buffers) { precondition(part.instrument!.sample.buffer === buffer) }
        precondition(!model.canUndoNotes(part: model.parts[0].id, clip: model.parts[0].primaryClipID))
        let events = try model.timeline()
        let introEnd = 8 * 60.0 / model.tempo, chorusStart = 24 * 60.0 / model.tempo
        precondition(!events.contains { $0.part == ids[1] && $0.time < introEnd })
        precondition(events.contains { $0.part == ids[1] && $0.time >= chorusStart })
        let adopted = directory.appendingPathComponent("adopted.sfensemble")
        let adoptedSaved = await model.save(to: adopted, remember: false); precondition(adoptedSaved)
        let restored = EnsembleModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let loaded = await restored.load(adopted, remember: false); precondition(loaded)
        precondition(restored.sections == model.sections && restored.tempo == model.tempo)
        for (a, b) in zip(restored.parts, model.parts) {
            precondition(a.performance == b.performance && a.additionalClips == b.additionalClips && a.gainDB == b.gainDB && a.muted == b.muted)
        }
        let wav = directory.appendingPathComponent("arranged.wav")
        let exported = await restored.exportWAV(to: wav); precondition(exported)
        let asset = try AudioAsset.load(wav)
        precondition(asset.channels == 2 && asset.sampleRate == 48000 && asset.duration > 10 && asset.peaks[0].max()! > 0.00001)
        let originalAfter = try Data(contentsOf: saved); precondition(originalAfter == originalFile)
        if CommandLine.arguments.contains("--playback") {
            let current = try restored.arrangementBrief(prompt: "test")
            let candidate = try ArrangementGeneration.demo(current)
            restored.play()
            try await Task.sleep(nanoseconds: 200_000_000)
            precondition(restored.playing && restored.parts[0].voices > 0 && restored.parts[1].voices == 0)
            precondition(!restored.applyArrangement(candidate, brief: current))
            restored.stop(); precondition(!restored.playing && restored.parts.allSatisfy { $0.voices == 0 })
        }
        print("PASS: arrangement proposals, sparse/full demo, schema/HTTP/CLI fixtures, invalid/stale/cancel atomicity, adoption, instruments, save/reload and WAV reimport")
    }
}
