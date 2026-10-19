import Foundation
import AVFoundation
import Darwin

enum SeparationTests {
    @MainActor static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-SeparationTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.wav")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
            buffer.frameLength = 4410
            for c in 0..<2 { for i in 0..<4410 { buffer.floatChannelData![c][i] = Float(sin(Double(i) * .pi * 2 * 440 / 44100) * 0.2) } }
            try file.write(from: buffer)
        }
        let fixture = root.appendingPathComponent("worker.py")
        try """
        import sys,json,shutil,pathlib,hashlib
        r=json.loads(pathlib.Path(sys.argv[2]).read_text()); d=pathlib.Path(sys.argv[2]).parent
        entries=[]
        for name in ['original','drums','bass','other','vocals']:
            shutil.copyfile(r['input'],d/(name+'.wav'))
            entries.append(dict(id=name,file=name+'.wav',frames=4410,sampleRate=44100,channels=2))
        (d/'manifest.json').write_text(json.dumps(dict(version=1,jobID=r['jobID'],prepared=False,model='htdemucs',weightSHA256='\(SeparationClient.weightHash)',inputSHA256=hashlib.sha256(pathlib.Path(r['input']).read_bytes()).hexdigest(),versions={'fixture':'1'},gain=1.0,preprocessing='demucs-mlx-load_audio-44100-stereo-outer-normalization-v1',backend='mlx-metal',settings=dict(shifts=0,overlap=.25,segment=7.8,batch_size=1,attention_precision='fp32',compile=True),audio=entries)))
        """.write(to: fixture, atomically: true, encoding: .utf8)
        let directory = root.appendingPathComponent("success")
        let manifest = try await SeparationClient().run(python: URL(fileURLWithPath: "/usr/bin/python3"), worker: fixture,
            cache: root, source: source, directory: directory, jobID: "test", control: SeparationProcess(), update: { _ in })
        precondition(manifest.audio?.count == 5)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let valid = try Data(contentsOf: manifestURL)
        func reject(_ mutate: (inout [String: Any]) -> Void) throws {
            var value = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
            mutate(&value)
            try JSONSerialization.data(withJSONObject: value).write(to: manifestURL)
            do { _ = try SeparationClient.validate(directory, jobID: "test", prepare: false); fatalError("Invalid separation accepted") } catch {}
            try valid.write(to: manifestURL)
        }
        try reject { $0["jobID"] = "stale" }
        try reject { $0["weightSHA256"] = "wrong" }
        try reject { $0["audio"] = [] }
        try reject { $0["inputSHA256"] = "bad" }
        try reject { $0["gain"] = 0 }
        try reject { $0["preprocessing"] = "unknown" }
        try reject { $0["versions"] = [:] }
        try reject { $0["backend"] = "torch" }
        try reject { $0["settings"] = [:] }
        try reject { object in
            var entries = object["audio"] as! [[String: Any]]; entries[0]["file"] = "../source.wav"; object["audio"] = entries
        }
        let drums = directory.appendingPathComponent("drums.wav")
        try FileManager.default.removeItem(at: drums)
        try FileManager.default.createSymbolicLink(at: drums, withDestinationURL: source)
        do { _ = try SeparationClient.validate(directory, jobID: "test", prepare: false); fatalError("Escaping symlink accepted") } catch {}
        try FileManager.default.removeItem(at: drums)
        try FileManager.default.copyItem(at: source, to: drums)

        let model = PlayerModel()
        await model.load(source)
        await model.prepareInstrument()
        let oldSample = model.instrumentSample!
        precondition(model.instrumentDirty)
        // Failed replacement preserves both waveform and unsaved instrument.
        let broken = root.appendingPathComponent("bad.wav")
        try Data("bad".utf8).write(to: broken)
        let rejected = await model.useSeparatedAudio(broken)
        precondition(!rejected && model.asset?.url == source && model.instrumentSample?.buffer === oldSample.buffer && model.instrumentDirty)
        let used = await model.useSeparatedAudio(drums)
        precondition(used && model.asset?.url != drums && model.instrumentSample == nil)
        let retained = model.asset!.url
        try FileManager.default.removeItem(at: directory)
        precondition(FileManager.default.fileExists(atPath: retained.path))
        model.select(from: 0, to: 0.5)
        await model.prepareInstrument()
        let saved = root.appendingPathComponent("extracted.sfinstrument")
        await model.saveInstrument(sample: model.instrumentSample!, root: 60, to: saved, remember: false)
        precondition(!model.instrumentDirty)
        model.cleanup()
        precondition(!FileManager.default.fileExists(atPath: retained.path))
        let restored = PlayerModel()
        let opened = await restored.loadInstrument(saved, remember: false)
        precondition(opened && restored.instrumentSample!.duration > 0)
        restored.cleanup()

        let stall = root.appendingPathComponent("stall.py")
        try """
        import sys,json,pathlib,os,time,signal
        d=pathlib.Path(sys.argv[2]).parent
        signal.signal(signal.SIGTERM,signal.SIG_IGN)
        (d/'pid').write_text(str(os.getpid()))
        while True: time.sleep(.01)
        """.write(to: stall, atomically: true, encoding: .utf8)
        let cancelled = root.appendingPathComponent("cancelled")
        let control = SeparationProcess()
        let task = Task {
            try await SeparationClient().run(python: URL(fileURLWithPath: "/usr/bin/python3"), worker: stall,
                cache: root, source: source, directory: cancelled, jobID: "cancel", control: control, update: { _ in })
        }
        var workerPID: Int32?
        for _ in 0..<100 {
            if let text = try? String(contentsOf: cancelled.appendingPathComponent("pid"), encoding: .utf8),
               let pid = Int32(text) { workerPID = pid; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let pid = workerPID else { task.cancel(); _ = try? await task.value; throw AudioError.invalid("Fixture worker did not start") }
        task.cancel()
        do { _ = try await task.value; fatalError("Cancelled worker accepted") } catch {}
        precondition(kill(pid, 0) == -1 && errno == ESRCH)
        print("PASS: separation fixture/manifest/stale/path/symlink validation, cancel kills worker, failed adoption preservation, owned audio lifetime and self-contained instrument roundtrip")
    }
}
