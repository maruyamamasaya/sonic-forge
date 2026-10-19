import Foundation
import CryptoKit

/// Read the real-audio comparison excerpts and report production pitch suggestions, without adopting them.
@main struct PitchEvaluation {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw AudioError.invalid("評価フォルダと新しい出力JSONを指定してください。") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard output.pathExtension == "json", !FileManager.default.fileExists(atPath: output.path) else { throw AudioError.invalid("既存ファイルは上書きしません。新しい.jsonを指定してください。") }
        var results: [[String:Any]] = []
        for stem in ["bass","other","drums"] {
            let url = directory.appendingPathComponent(stem + "_extracted.wav")
            let sample = try InstrumentSample.load(url: url)
            let before = SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined()
            let started = ProcessInfo.processInfo.systemUptime
            let value = try PitchEstimator.estimate(sample)
            let elapsed = ProcessInfo.processInfo.systemUptime-started
            let after = SHA256.hash(data: try Data(contentsOf: url)).map { String(format:"%02x",$0) }.joined()
            precondition(before == after)
            results.append(["stem":stem,"input_sha256":before,"input_unchanged":true,"seconds":sample.duration,
                "analysis_seconds":elapsed,"status":value.reliability.rawValue,"voiced_fraction":value.voicedFraction,"windows":value.analyzedWindows,
                "candidates":value.candidates.map { ["note":$0.note,"hz":$0.frequency,"cents":$0.cents,"support":$0.support] as [String:Any] }])
        }
        let data = try JSONSerialization.data(withJSONObject: ["version":1,"method":"local filtered YIN-style CMND, production PitchEstimator","results":results],options:[.prettyPrinted,.sortedKeys])
        try data.write(to: output,options:.withoutOverwriting)
        print(String(data:data,encoding:.utf8)!)
    }
}
