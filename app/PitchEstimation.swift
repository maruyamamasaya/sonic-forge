import Foundation
import AVFoundation
import Combine

struct PitchCandidate: Equatable, Identifiable {
    var id: Int { note }
    let note: Int
    let frequency: Double
    let cents: Double
    let support: Double
}
struct PitchEstimate: Equatable {
    enum Reliability: String { case steady = "安定した候補", review = "要確認", unavailable = "推定できませんでした" }
    let candidates: [PitchCandidate]
    let reliability: Reliability
    let voicedFraction: Double
    let analyzedWindows: Int
    let warning: String
    var primary: PitchCandidate? { candidates.first }
}

/// Bounded, local monophonic pitch suggestion. Confidence is a heuristic, not a probability.
enum PitchEstimator {
    static func estimate(_ sample: InstrumentSample) throws -> PitchEstimate {
        let buffer = sample.buffer, sr = buffer.format.sampleRate
        guard sr.isFinite, sr >= 8000, sr <= 192000, let input = buffer.floatChannelData,
              (1...2).contains(buffer.format.channelCount), buffer.frameLength > 0,
              Double(buffer.frameLength) / sr <= 30 else { throw AudioError.invalid("音程推定の音源が無効です。") }
        let stride = max(1, Int(sr / 16000)), rate = sr / Double(stride)
        let count = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        struct Observation { let midi: Double; let frequency: Double; let clarity: Double }
        var observations: [Observation] = []
        var attempted = 0
        // Windowed-sinc anti-aliasing before decimation; channels stay independent to avoid cancellation.
        let radius = 24 * stride, cutoff = 0.4 / Double(stride)
        var filter = (-radius...radius).map { i -> Double in
            let sinc = i == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * Double(i)) / (.pi * Double(i))
            return sinc * (0.54 + 0.46 * cos(.pi * Double(i) / Double(radius)))
        }
        let total = filter.reduce(0,+); filter = filter.map { $0 / total }
        for channel in 0..<channels {
            try Task.checkCancellation()
            var samples: [Double] = []; samples.reserveCapacity(count / stride + 1)
            // Bounds are replicated at the edges. Reject invalid PCM instead of silently making a pitch.
            for i in 0..<count where !input[channel][i].isFinite { throw AudioError.invalid("音源に無効なサンプルがあります。") }
            for position in Swift.stride(from: 0, to: count, by: stride) {
                if position % (stride * 1024) == 0 { try Task.checkCancellation() }
                var value = 0.0
                for k in filter.indices { value += Double(input[channel][min(count-1,max(0, position + k - radius))]) * filter[k] }
                samples.append(value)
            }
            let size = min(4096, samples.count)
            guard size >= Int(rate * 0.065) else { continue }
            let windows = samples.count == size ? 1 : min(8, max(2, samples.count / (size / 4)))
            for window in 0..<windows {
                try Task.checkCancellation()
                let start = windows == 1 ? 0 : (samples.count-size) * window / (windows-1)
                var frame = Array(samples[start..<start+size])
                let mean = frame.reduce(0,+) / Double(size)
                for i in frame.indices { frame[i] -= mean }
                let rms = sqrt(frame.reduce(0) { $0 + $1*$1 } / Double(size))
                attempted += 1
                guard rms > 0.00056 else { continue } // approximately -65 dBFS
                let maxLag = min(Int(rate / 27), size / 3)
                let minLag = max(2, Int(rate / 2400))
                guard maxLag > minLag+2 else { continue }
                let pairs = size-maxLag
                var difference = [Double](repeating: 0, count: maxLag+1)
                for lag in 1...maxLag {
                    if lag % 32 == 0 { try Task.checkCancellation() }
                    var sum = 0.0
                    for i in 0..<pairs { let d = frame[i]-frame[i+lag]; sum += d*d }
                    difference[lag] = sum
                }
                var cmnd = [Double](repeating: 1, count: maxLag+1), cumulative = 0.0
                for lag in 1...maxLag { cumulative += difference[lag]; cmnd[lag] = cumulative > 1e-20 ? difference[lag] * Double(lag) / cumulative : 1 }
                var chosen: Int?
                var lag = minLag
                while lag < maxLag {
                    if cmnd[lag] < 0.15 {
                        while lag+1 <= maxLag && cmnd[lag+1] < cmnd[lag] { lag += 1 }
                        chosen = lag; break
                    }
                    lag += 1
                }
                guard let tau = chosen, tau > 1, tau < maxLag, cmnd[tau] < 0.15 else { continue }
                let a = cmnd[tau-1], b = cmnd[tau], c = cmnd[tau+1]
                let divisor = a-2*b+c
                let offset = abs(divisor) > 1e-12 ? max(-0.5,min(0.5,0.5*(a-c)/divisor)) : 0
                let frequency = rate / (Double(tau)+offset)
                let midi = 69 + 12 * log2(frequency / 440)
                guard midi.isFinite, (0...127).contains(midi) else { continue }
                observations.append(Observation(midi: midi, frequency: frequency, clarity: 1-cmnd[tau]))
            }
        }
        let fraction = attempted > 0 ? Double(observations.count) / Double(attempted) : 0
        let groups = Dictionary(grouping: observations, by: { Int($0.midi.rounded()) })
        let ordered = groups.sorted { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
            return lhs.key < rhs.key
        }
        let candidates = ordered.prefix(3).map { note, values -> PitchCandidate in
            let frequencies = values.map(\.frequency).sorted()
            let frequency = frequencies[frequencies.count/2]
            return PitchCandidate(note: note, frequency: frequency, cents: 1200 * log2(frequency / (440 * pow(2,Double(note-69)/12))),
                                  support: Double(values.count) / Double(max(1,observations.count)))
        }
        guard let best = candidates.first, observations.count >= 2, fraction >= 0.25 else {
            return PitchEstimate(candidates: [], reliability: .unavailable, voicedFraction: fraction, analyzedWindows: attempted,
                warning: "単音が続く部分を長めに切り出してください。短い音・無音・打楽器・和音では候補を出せない場合があります。")
        }
        let bestGroup = groups[best.note]!
        let spread = bestGroup.map { abs(1200*log2($0.frequency/best.frequency)) }.sorted()
        let stable = bestGroup.count >= 4 && fraction >= 0.7 && best.support >= 0.85 && spread[spread.count/2] < 15
        return PitchEstimate(candidates: candidates, reliability: stable ? .steady : .review, voicedFraction: fraction, analyzedWindows: attempted,
            warning: "単音を想定した推定です。和音・倍音・打楽器は誤検出や1オクターブの違いがあり得ます。採用前に試してください。微調律は行いません。")
    }
}

@MainActor final class PitchAnalysis: ObservableObject {
    @Published private(set) var result: PitchEstimate?
    @Published private(set) var running = false
    @Published private(set) var message: String?
    private(set) var source: ObjectIdentifier?
    private var retainedSource: AVAudioPCMBuffer?
    private var revision = UUID()
    private var worker: Task<PitchEstimate, Error>?
    func invalidate() {
        cancel(); source = nil; retainedSource = nil; result = nil; message = nil
    }
    func cancel() {
        if running { message = "推定を中止しました。" }
        revision = UUID(); worker?.cancel(); worker = nil; running = false
    }
    func analyze(_ sample: InstrumentSample) async {
        guard !running else { return }
        cancel(); result = nil; message = nil; source = ObjectIdentifier(sample.buffer); retainedSource = sample.buffer
        let token = revision
        running = true
        let job = Task.detached(priority: .userInitiated) { try PitchEstimator.estimate(sample) }
        worker = job
        defer { if revision == token { running = false; worker = nil } }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await job.value }, onCancel: { job.cancel() })
            guard revision == token, !Task.isCancelled else { return }
            result = value
        } catch is CancellationError { }
        catch { if revision == token { message = error.localizedDescription } }
    }
    func canApply(to sample: InstrumentSample, note: Int) -> Bool {
        !running && result != nil && source == ObjectIdentifier(sample.buffer) && NotePitch.rootRange.contains(note)
    }
}
