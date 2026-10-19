import Foundation
import AVFoundation
@main struct Scan {
 static func main() throws {
  var report:[[String:Any]]=[]
  let base=URL(fileURLWithPath:"build/midi-materials",isDirectory:true)
  for group in ["song-a","song-b","voice"] {
   for stem in group == "voice" ? ["input"] : ["bass","other","vocals"] {
    let url=base.appendingPathComponent(group+"/"+stem+".wav")
    let f=try AVAudioFile(forReading:url), rate=f.processingFormat.sampleRate
    var candidates:[[String:Any]]=[]
    for step in 0..<55 {
     let start=Double(step)*0.2, length=0.7
     let sample=try InstrumentSample.load(url:url,selection:AudioSelection(startFrame:Int64(start*rate),endFrame:Int64((start+length)*rate)))
     let value=try PitchEstimator.estimate(sample)
     if value.reliability == .steady, let best=value.primary, NotePitch.rootRange.contains(best.note), best.support >= 0.9 {
      var energy=0.0,peak=0.0
      for i in 0..<Int(sample.buffer.frameLength) {let x=Double(sample.buffer.floatChannelData![0][i]);energy+=x*x;peak=max(peak,abs(x))}
      let rms=sqrt(energy/Double(sample.buffer.frameLength))
      if rms > 0.002 {candidates.append(["start":start,"seconds":length,"root":best.note,"hz":best.frequency,"cents":best.cents,"support":best.support,"rms":rms,"peak":peak])}
     }
    }
    candidates.sort { ($0["rms"] as! Double) > ($1["rms"] as! Double) }
    report.append(["group":group,"stem":stem,"stable_candidates":candidates])
    print(group,stem,candidates.prefix(2))
   }
  }
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("pitch-scan.json"))
 }
}
