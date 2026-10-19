import Foundation
import AVFoundation
import CryptoKit

/// Build only stable analyzed local excerpts. No network, generative voice model or library mutation.
@main struct MIDIMaterialDemo {
    @MainActor static func main() async throws {
        let base=URL(fileURLWithPath:"build/midi-materials",isDirectory:true)
        let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        guard !FileManager.default.fileExists(atPath:out.path) else { throw AudioError.invalid("新しい出力先を指定してください。") }
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let scan=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("pitch-scan.json"))) as! [[String:Any]]
        var instruments:[String:EnsembleInstrument]=[:], report:[[String:Any]]=[]
        for item in scan {
            let group=item["group"] as! String, stem=item["stem"] as! String
            let candidates=item["stable_candidates"] as! [[String:Any]]
            guard let c=candidates.first else { report.append(["group":group,"stem":stem,"created":false,"reason":"No stable candidate"]);continue }
            let source=base.appendingPathComponent(group+"/"+stem+".wav")
            let before=try MaterialHash.file(source)
            let sourceInfo=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent(group+"/source.json"))) as! [String:Any]
            let start=c["start"] as! Double, duration=c["seconds"] as! Double, sourceRoot=c["root"] as! Int
            let rate=try AVAudioFile(forReading:source).processingFormat.sampleRate
            let raw=try InstrumentSample.load(url:source,selection:AudioSelection(startFrame:Int64((start*rate).rounded()),endFrame:Int64(((start+duration)*rate).rounded())))
            let estimate=try PitchEstimator.estimate(raw)
            guard estimate.reliability == .steady, let pitch=estimate.primary, pitch.note == sourceRoot else { throw AudioError.invalid("候補の再解析が一致しません。") }
            for registered in (group == "song-a" && stem == "bass" ? [sourceRoot,48] : [sourceRoot]) {
                let ratio=pow(2,(Double(registered-sourceRoot)-pitch.cents/100)/12)
                let count=Int(Double(raw.buffer.frameLength-1)/ratio)
                let buffer=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:rate,channels:1)!,frameCapacity:AVAudioFrameCount(count))!
                buffer.frameLength=AVAudioFrameCount(count)
                let data=buffer.floatChannelData![0], input=raw.buffer.floatChannelData!, channels=Int(raw.buffer.format.channelCount)
                var peak:Float=0
                for i in 0..<count {
                    let position=Double(i)*ratio, index=Int(position), mix=Float(position-Double(index))
                    var value:Float=0
                    for ch in 0..<channels { value += input[ch][index]*(1-mix)+input[ch][index+1]*mix }
                    data[i]=value/Float(channels);peak=max(peak,abs(data[i]))
                }
                guard peak>0.002 else { throw AudioError.invalid("モノラル化した候補が無音です。") }
                let gain=Float(pow(10,-1.0/20))/peak
                let fade=max(1,Int(rate*0.005))
                for i in 0..<count {data[i] *= gain*Float(min(1,min(Double(i)/Double(fade),Double(count-1-i)/Double(fade))))}
                let key=group+"-"+stem+(registered == sourceRoot ? "" : "-C3-register")
                let sample=InstrumentSample(buffer:buffer,name:key,selection:AudioSelection(startFrame:0,endFrame:Int64(count)))
                let loop=SampleLoop(enabled:true,startFrame:Int64(Double(count)*0.25),endFrame:Int64(Double(count)*0.85),crossfadeFrames:min(Int64(rate*0.05),Int64(Double(count)*0.2)))
                let envelope=ADSRParameters(attack:group == "voice" ? 0.12 : 0.02,decay:0.18,sustain:0.75,release:0.7)
                let instrument=EnsembleInstrument(sample:sample,root:registered,envelope:envelope,loop:loop,name:key)
                let url=out.appendingPathComponent(key+".sfinstrument")
                try InstrumentDocument.save(sample:sample,rootNote:registered,envelope:envelope,loop:loop,to:url)
                let restored=try EnsembleInstrument.load(url)
                precondition(restored.root == registered && restored.sample.buffer.frameLength == buffer.frameLength)
                instruments[key]=instrument
                let after=try MaterialHash.file(source);precondition(before == after)
                report.append(["group":group,"stem":stem,"created":true,"file":url.lastPathComponent,"source":sourceInfo,
                    "start_in_clip":start,"start_in_original":(sourceInfo["start_seconds"] as! Double)+start,"seconds_in_original":duration,
                    "source_wav_sha256":before,"source_unchanged":true,"estimated_root":sourceRoot,"estimated_cents":pitch.cents,
                    "instrument_root":registered,"resampling_ratio":ratio,"normalization_db":20*log10(Double(gain)),"note":"Edited sampler copy; origin sidecar, not a MaterialStore record"])
            }
        }
        guard let lead=instruments["song-b-vocals"],let bass=instruments["song-a-bass-C3-register"],let choir=instruments["voice-input"] else { throw AudioError.invalid("今回の試作に必要な安定候補がありません。") }
        let midi=try MIDIFileImport.load(URL(fileURLWithPath:"tests/Fixtures/gymnopedie_1.mid"))
        let right=try midi.parts[0].performance(start:0,end:117,tempo:midi.tempo)
        let left=try midi.parts[1].performance(start:0,end:117,tempo:midi.tempo)
        var chorus=right; chorus.name="Voice chorus texture"
        chorus.notes=right.notes.filter{$0.duration>=2 && (57...76).contains($0.pitch)}.map{ var n=$0;n.velocity=40;return n }
        var parts=[EnsemblePartSnapshot(name:"旋律・抽出歌声",instrument:lead,performance:right,gainDB:-4,muted:false),
                   EnsemblePartSnapshot(name:"低音と和音・抽出ベース",instrument:bass,performance:left,gainDB:-8,muted:false),
                   EnsemblePartSnapshot(name:"コーラス・ボイス素材",instrument:choir,performance:chorus,gainDB:-16,muted:false)]
        for i in parts.indices { parts[i].reverb=i==2 ? 30 : 15;parts[i].compressor=PartCompressor(enabled:true,thresholdDB:-10,headroomDB:40,makeupDB:24) }
        parts[0].pan=0.12;parts[1].pan = -0.12;parts[2].pan=0.25
        let snapshot=EnsembleSnapshot(tempo:72,masterDB:0,parts:parts,limiter:.standard)
        let song=out.appendingPathComponent("Gymnopedie-Local-Samples.sfensemble")
        try EnsembleDocument.save(snapshot,to:song)
        let loaded=try EnsembleDocument.load(song)
        precondition(loaded.parts.map(\.performance)==parts.map(\.performance))
        let wav=out.appendingPathComponent("Gymnopedie-Local-Samples.wav")
        try await EnsembleExport.write(loaded,to:wav)
        let audio=try AudioAsset.load(wav)
        let file=try AVAudioFile(forReading:wav,commonFormat:.pcmFormatFloat32,interleaved:false)
        let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:16384)!
        var peak=0.0,energy=0.0,total=0
        while file.framePosition<file.length {
            try file.read(into:buffer)
            for ch in 0..<2 {for i in 0..<Int(buffer.frameLength){let v=Double(buffer.floatChannelData![ch][i]);precondition(v.isFinite);peak=max(peak,abs(v));energy+=v*v;total+=1}}
        }
        precondition(peak>0.001 && peak<=1)
        let summary:[String:Any]=["instruments":report,"midi_warnings":midi.warnings,"tempo":72,"excerpt_end_beat":117,"render_seconds":audio.duration,"peak_dbfs":20*log10(peak),"rms_dbfs":10*log10(energy/Double(total)),"generated_instruments":instruments.count]
        try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("report.json"),options:.withoutOverwriting)
        print("PASS: \(instruments.count) analyzed instruments, direct production SMF import, 3 parts with voice texture, archive restore, \(audio.duration)s WAV peak \(20*log10(peak)) dBFS")
    }
}
