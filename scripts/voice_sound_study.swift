import Foundation
import AVFoundation

/// Local timbre comparison only. No AI, network, library or composition mutation.
@main struct VoiceSoundStudy {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw AudioError.invalid("新しい出力フォルダを指定してください。") }
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: out.path) else { throw AudioError.invalid("既存の出力先は上書きしません。") }
        let input = URL(fileURLWithPath: "build/midi-materials/voice/input.wav")
        let before = try MaterialHash.file(input)
        let rate = try AVAudioFile(forReading: input).processingFormat.sampleRate
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var reports: [[String: Any]] = []
        // Same stable anchor as the previous study; longer context is a candidate,
        // not a verified sustained vowel. Root remains an approximation for speech.
        for (name, start, duration, looped) in [
            ("01-short-dry", 1.4, 0.7, false),
            ("02-long-dry", 1.0, 1.6, false),
            ("03-short-loop", 1.4, 0.7, true)
        ] {
            let raw = try InstrumentSample.load(url: input, selection: AudioSelection(
                startFrame: Int64((start * rate).rounded()), endFrame: Int64(((start + duration) * rate).rounded())))
            // No tuning, denoising or stereo collapse. Only a common gain from
            // the original stable anchor, plus a 5 ms edge fade.
            let anchor = try InstrumentSample.load(url: input, selection: AudioSelection(
                startFrame: Int64((1.4 * rate).rounded()), endFrame: Int64((2.1 * rate).rounded())))
            var anchorPeak: Float = 0
            for ch in 0..<Int(anchor.buffer.format.channelCount) {
                for i in 0..<Int(anchor.buffer.frameLength) { anchorPeak = max(anchorPeak, abs(anchor.buffer.floatChannelData![ch][i])) }
            }
            guard anchorPeak > 0 else { throw AudioError.invalid("無音の比較素材です。") }
            let gain = Float(pow(10, -9.0 / 20)) / anchorPeak
            let count = Int(raw.buffer.frameLength), fade = rate * 0.005
            for ch in 0..<Int(raw.buffer.format.channelCount) {
                for i in 0..<count {
                    raw.buffer.floatChannelData![ch][i] *= gain * Float(min(1, min(Double(i), Double(count - 1 - i)) / fade))
                }
            }
            let sample = InstrumentSample(buffer: raw.buffer, name: name, selection: AudioSelection(startFrame: 0, endFrame: Int64(count)))
            let loop = SampleLoop(enabled: looped, startFrame: Int64(Double(count) * 0.25), endFrame: Int64(Double(count) * 0.85), crossfadeFrames: Int64(rate * 0.05))
            let envelope = ADSRParameters(attack: 0.005, decay: 0, sustain: 1, release: 0.08)
            let instrument = EnsembleInstrument(sample: sample, root: 68, envelope: envelope, loop: loop, name: name)
            try InstrumentDocument.save(sample: sample, rootNote: 68, envelope: envelope, loop: loop, to: out.appendingPathComponent(name + ".sfinstrument"))
            // Root, -2, +2, then root/major-third/fifth. Two-second holds expose
            // one-shot exhaustion versus looping. No other parts or effects.
            var notes = [68, 66, 70].enumerated().map {
                PerformanceNote(beat: Double($0.offset) * 3, duration: 2, pitch: $0.element, velocity: 100)
            }
            notes += [68, 72, 75].map { PerformanceNote(beat: 9, duration: 2, pitch: $0, velocity: 60) }
            let performance = PerformanceDocument(name: name, tempo: 60, notes: notes, pedals: [])
            let snapshot = EnsembleSnapshot(tempo: 60, masterDB: -9, parts: [
                EnsemblePartSnapshot(name: name, instrument: instrument, performance: performance, gainDB: 0, muted: false)
            ])
            let archive = out.appendingPathComponent(name + ".sfensemble")
            try EnsembleDocument.save(snapshot, to: archive)
            let loaded = try EnsembleDocument.load(archive)
            let wav = out.appendingPathComponent(name + ".wav")
            try await EnsembleExport.write(loaded, to: wav)
            let asset = try AudioAsset.load(wav)
            let rendered = try InstrumentSample.load(url: wav)
            var peak: Float = 0, energy = 0.0, total = 0
            for ch in 0..<Int(rendered.buffer.format.channelCount) {
                for i in 0..<Int(rendered.buffer.frameLength) {
                    let v = rendered.buffer.floatChannelData![ch][i]
                    guard v.isFinite else { throw AudioError.invalid("非有限の出力です。") }
                    peak = max(peak, abs(v)); energy += Double(v * v); total += 1
                }
            }
            guard peak > 0.001, peak < 1 else { throw AudioError.invalid("無音またはクリップした出力です。") }
            reports.append(["name": name, "source_start_in_clip": start, "source_seconds": duration,
                "source_start_in_original": 8 + start, "root": 68, "loop": looped, "common_gain": gain,
                "output_seconds": asset.duration, "peak_dbfs": 20 * log10(Double(peak)), "rms_dbfs": 10 * log10(energy / Double(total))])
            print("PASS: \(name), \(asset.duration)s, peak \(peak)")
        }
        guard before == (try MaterialHash.file(input)) else { throw AudioError.invalid("元音源が変更されています。") }
        try JSONSerialization.data(withJSONObject: ["source_sha256": before, "source_unchanged": true,
            "vowel_verified_by_listener": false, "studies": reports], options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("report.json"), options: .withoutOverwriting)
    }
}
