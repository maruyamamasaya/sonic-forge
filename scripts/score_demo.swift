import Foundation
import AVFoundation
import CryptoKit

/// A fixed musical example, using existing sampler/archive/export APIs without changing the app.
@main struct ScoreDemo {
    @MainActor static func main() async throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let corpusURL = URL(fileURLWithPath: "app/Resources/PitchCorpus", isDirectory: true)
        let corpus = try PitchCorpus.load(at: corpusURL)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: corpusURL.appendingPathComponent("manifest.json"))) as! [String:Any]
        let sourceIndex = manifest["sources"] as! [[String:Any]]
        var preparation: [[String:Any]] = []
        func sha(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined() }
        func instrument(id: String, sourceID: String?, start: Double = 0, root: Int, name: String, looped: Bool) throws -> EnsembleInstrument {
            let entry = corpus.entries.first { $0.id == id }!
            let referenceURL = try PitchCorpus.verifiedURL(entry, in: corpusURL)
            let estimate = try PitchEstimator.estimate(InstrumentSample.load(url: referenceURL))
            guard let candidate = estimate.primary, candidate.note == root, abs(candidate.cents) < 50 else { throw AudioError.invalid("調律用の名目基準音と候補が一致しません。") }
            let source: URL
            let raw: InstrumentSample
            if let sourceID {
                source = URL(fileURLWithPath: "build/pitch-corpus-source/\(sourceID).aif")
                guard let item = sourceIndex.first(where: { $0["id"] as? String == sourceID }), try sha(source) == item["sha256"] as? String else { throw AudioError.invalid("原録音のハッシュを確認できません。先に音程評価用の原録音を準備してください。") }
                let file = try AVAudioFile(forReading: source)
                raw = try InstrumentSample.load(url: source, selection: AudioSelection(startFrame: Int64((start*file.processingFormat.sampleRate).rounded()), endFrame: Int64(((start+8)*file.processingFormat.sampleRate).rounded())))
            } else {
                source = referenceURL
                raw = try InstrumentSample.load(url: source)
            }
            let before = try sha(source)
            let tuningRatio = pow(2,-candidate.cents/1200)
            let count = Int(Double(raw.buffer.frameLength-1)/tuningRatio)
            let rate = raw.buffer.format.sampleRate
            let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            let input = raw.buffer.floatChannelData!, output = buffer.floatChannelData![0], channels = Int(raw.buffer.format.channelCount)
            var peak: Float = 0
            for i in 0..<count {
                let position = Double(i)*tuningRatio, index = Int(position), fraction = Float(position-Double(index))
                var value: Float = 0
                for c in 0..<channels { value += input[c][index]*(1-fraction)+input[c][index+1]*fraction }
                output[i] = value/Float(channels); peak = max(peak,abs(output[i]))
            }
            guard peak > 0 else { throw AudioError.invalid("試作素材が無音です。") }
            let gain = Float(pow(10,-1.0/20))/peak
            for i in 0..<count { output[i] *= gain }
            let sample = InstrumentSample(buffer: buffer, name: name, selection: AudioSelection(startFrame: 0, endFrame: Int64(count)))
            let loop = looped ? SampleLoop(enabled: true, startFrame: Int64(rate*0.45), endFrame: Int64(rate*1.05), crossfadeFrames: Int64(rate*0.06)) : SampleLoop(endFrame: Int64(count))
            let envelope = ADSRParameters(attack: looped ? 0.012 : 0.004, decay: 0.18, sustain: looped ? 0.68 : 0.95, release: looped ? 0.55 : 0.65)
            let value = EnsembleInstrument(sample: sample, root: root, envelope: envelope, loop: loop, name: name)
            try InstrumentDocument.save(sample: sample, rootNote: root, envelope: envelope, loop: loop, to: out.appendingPathComponent(name+".sfinstrument"))
            let after = try sha(source)
            precondition(after == before)
            preparation.append(["id":id,"source_sha256":before,"source_unchanged":true,"root":root,"estimated_cents":candidate.cents,
                "copy_tuning_cents":-candidate.cents,"copy_gain_db":20*log10(Double(gain)),"copy_peak_dbfs":-1,"seconds":sample.duration,"loop":looped])
            return value
        }
        let piano = try instrument(id: "piano-mf-C4", sourceID: "piano-mf-C4", start: 0.5, root: 60, name: "Iowa Piano C4", looped: false)
        let lowPiano = try instrument(id: "piano-mf-C2", sourceID: "piano-mf-C2", start: 0.6, root: 36, name: "Iowa Piano C2", looped: false)
        let guitar = try instrument(id: "guitar-mf-B3", sourceID: "guitar-B3-mf", start: 0.1, root: 59, name: "Iowa Guitar B3", looped: true)
        let bass = try instrument(id: "bass-mf-B1", sourceID: nil, root: 35, name: "Iowa Bowed Bass B1", looped: true)
        let documents = try ["melody","harmony","bass"].map { try PerformanceDocument.load(out.appendingPathComponent($0+".sfperformance")) }
        let sections = [EnsembleSection(name: "序奏と主題 · 1–12小節", beats: 36), EnsembleSection(name: "主題の続き · 13–21小節", beats: 27), EnsembleSection(name: "展開 · 22–31小節", beats: 30), EnsembleSection(name: "第1終止 · 32–39小節", beats: 24)]
        var measurements: [[String:Any]] = []
        for wooden in [false,true] {
            let prefix = wooden ? "Gymnopedie-Woodland" : "Gymnopedie-Piano"
            var parts = [EnsemblePartSnapshot(name: wooden ? "旋律・ギター" : "旋律・ピアノ", instrument: wooden ? guitar : piano, performance: documents[0], gainDB: 0, muted: false),
                EnsemblePartSnapshot(name: "和音・ピアノ", instrument: piano, performance: documents[1], gainDB: -3, muted: false),
                EnsemblePartSnapshot(name: wooden ? "低音・コントラバス" : "低音・ピアノ", instrument: wooden ? bass : lowPiano, performance: documents[2], gainDB: wooden ? -7 : -4, muted: false)]
            parts[0].pan = 0.12; parts[1].pan = -0.15; parts[2].pan = -0.04
            for i in parts.indices {
                parts[i].reverb = wooden ? 20 : 12
                parts[i].compressor = PartCompressor(enabled: true, thresholdDB: -10, headroomDB: 40, makeupDB: 24)
            }
            let song = EnsembleSnapshot(tempo: 72, masterDB: 0, parts: parts, sections: sections, limiter: .standard)
            let songURL = out.appendingPathComponent(prefix+".sfensemble")
            try EnsembleDocument.save(song, to: songURL)
            let restored = try EnsembleDocument.load(songURL)
            precondition(restored.parts.map(\.performance) == documents && restored.sections == sections)
            let wav = out.appendingPathComponent(prefix+".wav")
            try await EnsembleExport.write(restored, to: wav, protecting: [songURL])
            let asset = try AudioAsset.load(wav)
            let file = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384)!
            var peak = 0.0, sum = 0.0, samples = 0
            while file.framePosition < file.length {
                try file.read(into: buffer)
                for c in 0..<Int(buffer.format.channelCount) { for i in 0..<Int(buffer.frameLength) {
                    let x = Double(buffer.floatChannelData![c][i]); precondition(x.isFinite)
                    peak = max(peak,abs(x)); sum += x*x; samples += 1
                } }
            }
            precondition(peak > 0.0001 && peak <= 1 && asset.channels == 2 && asset.sampleRate == 48000)
            measurements.append(["file":wav.lastPathComponent,"seconds":asset.duration,"peak_dbfs":20*log10(peak),"rms_dbfs":10*log10(sum/Double(samples)),"sha256":try sha(wav),"finite":true,"not_silent":true,"archive_reload":true])
            print("PASS: \(prefix), \(asset.duration)s, peak \(20*log10(peak)) dBFS, save/reload and WAV decode")
        }
        try JSONSerialization.data(withJSONObject:["instruments":preparation,"renders":measurements],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("render-report.json"),options:.withoutOverwriting)
    }
}
