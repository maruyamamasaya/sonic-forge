import Foundation

/// Check the exact shared demo/evaluation recordings; measure accuracy in the evaluation runner.
enum PitchCorpusTests {
    static func run() throws {
        let directory = URL(fileURLWithPath: "app/Resources/PitchCorpus", isDirectory: true)
        let corpus = try PitchCorpus.load(at: directory)
        for group in ["bass", "piano", "guitar", "chord", "percussion"] {
            precondition(corpus.entries.contains { $0.group == group })
        }
        for entry in corpus.entries {
            let url = try PitchCorpus.verifiedURL(entry, in: directory)
            let sample = try InstrumentSample.load(url: url)
            precondition(sample.duration >= 0.1 && sample.duration <= 2)
            let result = try PitchEstimator.estimate(sample)
            precondition(result.candidates.allSatisfy { $0.frequency.isFinite && $0.cents.isFinite })
            _ = try PitchCorpus.verifiedURL(entry, in: directory)
        }
        let bad = PitchCorpus.Entry(id: "missing", group: "bass", label: "missing", file: "missing.wav", notes: [28], kind: "single", sha256: "invalid")
        do { _ = try PitchCorpus.verifiedURL(bad, in: directory); fatalError("Missing corpus input accepted") } catch {}
        print("PASS: recorded pitch corpus categories, hashes, decoding, finite production estimates and unchanged audio")
    }
}
