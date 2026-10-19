import Foundation

@main struct PitchCorpusEvaluation {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func run() throws {
        guard CommandLine.arguments.count == 3 else { throw AudioError.invalid("音源フォルダと新しい出力JSONを指定してください。") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard output.pathExtension == "json", !FileManager.default.fileExists(atPath: output.path) else { throw AudioError.invalid("新しい.jsonを指定してください。既存結果は上書きしません。") }
        let corpus = try PitchCorpus.load(at: directory)
        var results: [[String:Any]] = []
        for entry in corpus.entries {
            let url = try PitchCorpus.verifiedURL(entry, in: directory)
            let sample = try InstrumentSample.load(url: url)
            let started = ProcessInfo.processInfo.systemUptime
            let value = try PitchEstimator.estimate(sample)
            let elapsed = ProcessInfo.processInfo.systemUptime-started
            _ = try PitchCorpus.verifiedURL(entry, in: directory)
            var row: [String:Any] = ["id":entry.id,"group":entry.group,"kind":entry.kind,"label":entry.label,"reference_notes":entry.notes,
                "input_sha256":entry.sha256,"input_unchanged":true,"seconds":sample.duration,"analysis_seconds":elapsed,
                "status":value.reliability.rawValue,"voiced_fraction":value.voicedFraction,"windows":value.analyzedWindows,
                "candidates":value.candidates.map { ["note":$0.note,"hz":$0.frequency,"cents":$0.cents,"support":$0.support] as [String:Any] }]
            if entry.kind == "single" {
                let expected = entry.notes[0]
                row["top1_correct"] = value.primary?.note == expected
                row["top3_contains_reference"] = value.candidates.contains { $0.note == expected }
                if let primary = value.primary {
                    let delta = primary.note-expected
                    row["semitone_error"] = delta
                    row["octave_error"] = delta != 0 && delta % 12 == 0
                    row["reference_cents_error"] = 1200 * log2(primary.frequency / (440 * pow(2,Double(expected-69)/12)))
                }
            } else {
                row["steady_on_non_single"] = value.reliability == .steady
            }
            results.append(row)
            print("\(entry.id): \(value.reliability.rawValue), notes=\(value.candidates.map(\.note)), expected=\(entry.notes)")
        }
        var summaries: [[String:Any]] = []
        for group in ["bass","piano","guitar","chord","percussion"] {
            let rows = results.filter { $0["group"] as? String == group }
            summaries.append(["group":group,"count":rows.count,
                "top1_correct":rows.filter { $0["top1_correct"] as? Bool == true }.count,
                "top3_contains_reference":rows.filter { $0["top3_contains_reference"] as? Bool == true }.count,
                "octave_errors":rows.filter { $0["octave_error"] as? Bool == true }.count,
                "unavailable":rows.filter { $0["status"] as? String == PitchEstimate.Reliability.unavailable.rawValue }.count,
                "steady_on_non_single":rows.filter { $0["steady_on_non_single"] as? Bool == true }.count])
        }
        let data = try JSONSerialization.data(withJSONObject: ["version":1,"corpus_version":corpus.version,"method":"production PitchEstimator; A4=440; source nominal notes, no independent tuning measurement","summary":summaries,"results":results], options:[.prettyPrinted,.sortedKeys])
        try data.write(to: output, options:.withoutOverwriting)
        print(String(data: try JSONSerialization.data(withJSONObject:summaries,options:.prettyPrinted),encoding:.utf8)!)
    }
}
