import Foundation
import AVFoundation
import Darwin

/// Offline rendering uses the same sampler, pedal ownership and mix as playback.
@MainActor
enum EnsembleExport {
    static let sampleRate = 48_000.0
    static let maximumFrames = Int64((256 * 1024 * 1024 - 4096) / 8)

    static func write(_ snapshot: EnsembleSnapshot, to destination: URL, protecting sources: [URL] = [],
                      progress: (Double) -> Void = { _ in }) async throws {
        try EnsembleDocument.validate(snapshot)
        guard destination.pathExtension.lowercased() == "wav" else { throw AudioError.invalid(".wav形式を指定してください。") }
        func protect() throws {
            guard !sources.contains(where: { WAVExport.sameFile($0, destination) }) else {
                throw AudioError.invalid("元の音源・楽器・構成には上書きできません。別名で保存してください。")
            }
        }
        try protect()
        var events: [(frame: Int64, part: Int, bytes: [UInt8])] = []
        for (index, part) in snapshot.parts.enumerated() {
            events += try EnsembleClips.events(part.allClips, root: part.instrument.root, tempo: snapshot.tempo, sections: snapshot.sections).map {
                (Int64(($0.time * sampleRate).rounded(.up)), index, $0.bytes)
            }
        }
        events = events.enumerated().sorted {
            $0.element.frame == $1.element.frame ? $0.offset < $1.offset : $0.element.frame < $1.element.frame
        }.map(\.element)
        let tail = snapshot.parts.map { $0.instrument.envelope.release + ($0.muted ? 0 : PartReverb.tailSeconds($0.reverb)) }.max() ?? 0
        let sectionEnd = Int64((EnsembleSections.end(snapshot.sections) * 60 / snapshot.tempo * sampleRate).rounded(.up))
        let end = max(events.last?.frame ?? 0, sectionEnd) + Int64(((tail + 0.05) * sampleRate).rounded(.up))
        guard end > 0, end <= maximumFrames else { throw AudioError.invalid("書き出すWAVが256 MBを超えます。開始位置や演奏を短くしてください。") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".sonicforge-ensemble-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let engine = AVAudioEngine()
        var voices: [EnsembleVoice] = []
        defer { voices.forEach { $0.stop() }; engine.stop() }
        for (index, part) in snapshot.parts.enumerated() {
            let mixer = AVAudioMixerNode(); engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, fromBus: 0, toBus: AVAudioNodeBus(index), format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!)
            let voice = EnsembleVoice(instrument: part.instrument, engine: engine, mixer: mixer)
            voice.sampler.gain = part.muted ? 0 : Float(pow(10, part.gainDB / 20))
            voices.append(voice)
        }
        engine.mainMixerNode.outputVolume = Float(pow(10, snapshot.masterDB / 20)) / Float(EnsembleModel.maximumParts)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) else { throw AudioError.invalid("書き出しメモリを確保できません。") }
        engine.prepare(); try engine.start()
        // Mixer connection parameters must be set after the graph is initialized.
        for (voice, part) in zip(voices, snapshot.parts) {
            voice.sampler.gain = part.muted ? 0 : Float(pow(10, part.gainDB / 20))
            voice.sampler.pan = Float(part.pan); voice.setEQ(part.eq); voice.setReverb(part.reverb)
        }
        // Close the file before publishing it by atomic rename.
        do {
            var settings = format.settings; settings[AVLinearPCMIsNonInterleaved] = false
            let file = try AVAudioFile(forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            var frame: Int64 = 0, cursor = 0, retries = 0, blocks = 0
            while frame < end {
                try Task.checkCancellation()
                while cursor < events.count && events[cursor].frame <= frame {
                    try voices[events[cursor].part].receive(events[cursor].bytes); cursor += 1
                }
                let next = cursor < events.count ? events[cursor].frame : end
                let count = AVAudioFrameCount(min(512, min(end - frame, next - frame)))
                let status = try engine.renderOffline(count, to: buffer)
                switch status {
                case .success:
                    guard buffer.frameLength > 0 else { throw AudioError.invalid("WAVレンダーが進みませんでした。") }
                    try file.write(from: buffer); frame += Int64(buffer.frameLength); retries = 0
                    voices.forEach { $0.sampler.refreshCompletion() }
                case .cannotDoInCurrentContext:
                    retries += 1
                    guard retries < 100 else { throw AudioError.invalid("WAVレンダーを継続できませんでした。") }
                default: throw AudioError.invalid("WAVレンダーに失敗しました。")
                }
                blocks += 1
                if blocks % 32 == 0 { progress(Double(frame) / Double(end)); await Task.yield() }
            }
        }
        try Task.checkCancellation(); try protect()
        let status = temporary.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in Darwin.rename(from!, to!) }
        }
        if status != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        progress(1)
    }
}
