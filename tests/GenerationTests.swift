import Foundation

// Tests use fake transports and an isolated local CLI fixture. No paid request in Full.
enum GenerationTests {
    @MainActor static func run() async throws {
        let brief = PerformanceBrief(prompt: "落ち着いた和音", root: 57)
        let calm = try PerformanceGeneration.demo(brief)
        let bouncy = try PerformanceGeneration.demo(PerformanceBrief(prompt: "少し跳ねたフレーズ", root: 57))
        precondition(calm.notes.count == 12 && bouncy.notes.count == 32 && calm.tempo < bouncy.tempo)
        precondition(calm.notes[0].pitch == 57 && bouncy.notes[1].beat == 0.65)
        func reject(_ data: Data) {
            do { _ = try PerformanceGeneration.decode(data, root: 57); fatalError("Invalid generation accepted") } catch {}
        }
        reject(Data("bad".utf8)); reject(Data(repeating: 32, count: PerformanceGeneration.byteLimit + 1))
        var invalid = calm; invalid.notes[0].pitch = 100; reject(try JSONEncoder().encode(invalid))
        invalid = calm; invalid.notes[0].duration = 17; reject(try JSONEncoder().encode(invalid))
        invalid = calm; invalid.notes.append(invalid.notes[0]); reject(try JSONEncoder().encode(invalid))
        invalid = calm; invalid.notes = (0..<65).map { PerformanceNote(beat: Double($0) * 0.2, duration: 0.1, pitch: 57, velocity: 70) }
        reject(try JSONEncoder().encode(invalid))
        invalid = calm; invalid.pedals = [PerformancePedal(beat: 0, down: true)]; reject(try JSONEncoder().encode(invalid))
        let request = try OpenAIPerformanceClient.request(brief: brief, key: "test-key", model: "test-model")
        precondition(request.url!.absoluteString == "https://api.openai.com/v1/responses" && request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["store"] as? Bool == false && body["model"] as? String == "test-model")
        precondition(String(data: request.httpBody!, encoding: .utf8)!.contains("57"))
        let format = (body["text"] as! [String: Any])["format"] as! [String: Any]
        precondition(format["strict"] as? Bool == true && format["type"] as? String == "json_schema")
        let schema = format["schema"] as! [String: Any]
        precondition(Set(schema["required"] as! [String]) == Set(["version", "name", "tempo", "transpose", "velocityPercent", "notes", "pedals"]))
        let json = String(data: try JSONEncoder().encode(calm), encoding: .utf8)!
        let responseData = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": json]]]]])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let client = OpenAIPerformanceClient(transport: { _ in (responseData, response) })
        let result = try await client.generate(brief: brief, key: "test-key", model: "test-model")
        precondition(result == calm)
        for status in [401, 403, 429, 500] {
            let bad = OpenAIPerformanceClient(transport: { _ in
                (Data("do not expose this server text or test-key".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await bad.generate(brief: brief, key: "test-key", model: "test-model"); fatalError("HTTP error accepted") }
            catch { precondition(!error.localizedDescription.contains("test-key") && !error.localizedDescription.contains("server text")) }
        }
        for object: [String: Any] in [
            ["status": "incomplete", "output": []],
            ["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "private text"]]]]],
            ["status": "completed", "output": []]
        ] {
            do { _ = try OpenAIPerformanceClient.decodeResponse(JSONSerialization.data(withJSONObject: object), root: 57); fatalError("Invalid response accepted") } catch {}
        }
        let composer = PerformanceComposer()
        composer.provider = .demo; composer.generate(root: 57)
        while composer.generating { await Task.yield() }
        precondition(composer.candidate == calm && composer.candidateRoot == 57 && composer.source == "Demo")
        composer.generate(root: 57, override: { brief in
            // A transport that ignores cancellation cannot publish stale results.
            try? await Task.sleep(nanoseconds: 100_000_000)
            return try PerformanceGeneration.demo(brief)
        })
        await Task.yield(); composer.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(composer.candidate == nil && !composer.generating)
        composer.provider = .external; composer.externalJSON = json; composer.generate(root: 57)
        while composer.generating { await Task.yield() }
        precondition(composer.candidate == calm)
        composer.prompt = "changed"; precondition(composer.candidate == nil)
        let midi = MIDIInput()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-GenerationTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = directory.appendingPathComponent("saved.sfperformance")
        precondition(midi.savePerformance(to: saved))
        precondition(midi.applyGeneratedPerformance(calm, root: 57) && midi.performanceDirty && midi.performanceFileURL == nil)
        let previous = midi.performance
        precondition(!midi.applyGeneratedPerformance(invalid, root: 57) && midi.performance == previous)
        let generated = directory.appendingPathComponent("generated.sfperformance")
        precondition(midi.savePerformance(to: generated) && midi.loadPerformance(generated) && midi.performance == calm)
        // Local executable fixture tests Process arguments/stdin/output without invoking an AI.
        let fixture = directory.appendingPathComponent("fixture.json")
        try JSONEncoder().encode(calm).write(to: fixture)
        let executable = directory.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        set -eu
        output=''
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '--output-last-message' ]; then output="$2"; shift; fi
            shift
        done
        cat >/dev/null
        cp '\(fixture.path)' "$output"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let cli = try await CodexPerformanceClient().generate(brief: brief, executable: executable.path)
        precondition(cli == calm)
        let arguments = CodexPerformanceClient.arguments(directory: directory, schema: fixture, output: generated)
        precondition(arguments.contains("read-only") && arguments.contains("--ignore-user-config") && arguments.contains("shell_tool") && arguments.last == "-")
        let slow = "#!/bin/sh\nexec /bin/sleep 10\n"
        try slow.write(to: executable, atomically: true, encoding: .utf8)
        do { _ = try await CodexPerformanceClient().generate(brief: brief, executable: executable.path, timeout: 0.1); fatalError("Timeout ignored") } catch {}
        print("PASS: generation demo/root/rhythm, API schema/HTTP/refusal/incomplete handling, CLI subprocess/timeout, cancellation, candidate validation and save/reload")
    }
    @MainActor static func integration() async throws {
        let model = PlayerModel()
        await model.loadDemo()
        let original = model.instrumentSample?.name
        for prompt in ["落ち着いた和音", "少し跳ねたフレーズ"] {
            var document = try PerformanceGeneration.demo(PerformanceBrief(prompt: prompt, root: model.rootNote))
            document.tempo = 240
            precondition(model.midi.applyGeneratedPerformance(document, root: model.rootNote))
            model.suspendMIDI(false); model.midi.playPerformance()
            try await Task.sleep(nanoseconds: 180_000_000)
            precondition(model.midi.performing && !model.activeNotes.isEmpty && model.soundingVoices > 0)
            precondition(model.instrumentSample?.name == original)
            model.stopInstrument()
            precondition(!model.midi.performing && model.activeNotes.isEmpty)
        }
        model.cleanup()
        print("PASS: generated calm/bouncy performances through virtual CoreMIDI on demo instrument and all-notes-off")
    }
    @MainActor static func live() async throws {
        let brief = PerformanceBrief(prompt: "落ち着いた和音。ゆっくり、柔らかい強弱で。", root: 57)
        let document = try await CodexPerformanceClient().generate(brief: brief, executable: CodexPerformanceClient.discover())
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/ai-live.sfperformance")
        try document.save(to: url)
        let model = PlayerModel(); await model.loadDemo()
        precondition(model.midi.loadPerformance(url))
        model.suspendMIDI(false); model.midi.playPerformance()
        try await Task.sleep(nanoseconds: 600_000_000)
        precondition(model.soundingVoices > 0)
        model.stopInstrument(); model.cleanup()
        print("PASS: live Codex CLI generated/validated/saved/reloaded performance and demo instrument playback")
    }
}
