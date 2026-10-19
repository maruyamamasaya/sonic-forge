import Foundation
import AVFoundation

enum PitchEstimationTests {
    static func sample(rate: Double = 44100, seconds: Double = 0.45, channels: AVAudioChannelCount = 1,
                       signal: (Double, Int) -> Double) -> InstrumentSample {
        let frames = Int(seconds*rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<Int(channels) { for i in 0..<frames { buffer.floatChannelData![c][i] = Float(signal(Double(i)/rate,c)) } }
        return InstrumentSample(buffer: buffer, name: "Pitch fixture", selection: AudioSelection(startFrame: 0, endFrame: Int64(frames)))
    }
    @MainActor static func run() async throws {
        for rate in [44100.0,48000] { for note in [24,39,57,69,96] {
            let hz = 440 * pow(2, Double(note-69)/12)
            let sine = sample(rate: rate) { t,_ in 0.4*sin(2 * .pi * hz*t) }
            let result = try PitchEstimator.estimate(sine)
            precondition(result.primary?.note == note, "Sine note \(note) at \(rate): \(result)")
            precondition(abs(result.primary!.cents) < 30, "Pitch interpolation outside expected tolerance")
        } }
        let hz = 440 * pow(2,Double(39-69)/12)
        let harmonic = sample(channels: 2) { t,c in
            let value = 0.22*sin(2 * .pi * 2*hz*t) + 0.22*sin(2 * .pi * 3*hz*t)
            return c == 0 ? value : -value
        }
        let result_harmonic = try PitchEstimator.estimate(harmonic)
        precondition(result_harmonic.primary?.note == 39)
        let detuned = sample { t,_ in 0.4*sin(2 * .pi * 440*pow(2,0.32/12)*t) }
        let tuning = try PitchEstimator.estimate(detuned)
        precondition(tuning.primary?.note == 69 && abs(tuning.primary!.cents - 32) < 8)
        let silence = sample { _,_ in 0 }
        let result_silence = try PitchEstimator.estimate(silence)
        precondition(result_silence.primary == nil)
        let short = sample(seconds: 0.02) { t,_ in sin(2 * .pi * hz*t) }
        let result_short = try PitchEstimator.estimate(short)
        precondition(result_short.primary == nil)
        var seed: UInt64 = 12345
        let noise = sample { _,_ in seed = seed &* 6364136223846793005 &+ 1; return (Double(seed >> 32)/Double(UInt32.max) - 0.5) * 0.6 }
        let result_noise = try PitchEstimator.estimate(noise)
        precondition(result_noise.reliability == .unavailable)
        let changing = sample(seconds: 1.4) { t,_ in 0.4*sin(2 * .pi * (t < 0.7 ? hz : 220)*t) }
        let result_changing = try PitchEstimator.estimate(changing)
        precondition(result_changing.reliability != .steady)
        let bad = sample { _,_ in .nan }
        do { _ = try PitchEstimator.estimate(bad); fatalError("Nonfinite pitch input accepted") } catch {}
        let low = sample { t,_ in 0.4*sin(2 * .pi * 30.87*t) }
        let outside = try PitchEstimator.estimate(low)
        precondition(outside.primary?.note == 23) // Never silently clamp to C1.
        let analyzer = PitchAnalysis()
        await analyzer.analyze(harmonic)
        precondition(analyzer.result?.primary?.note == 39 && analyzer.canApply(to: harmonic, note: 39))
        precondition(!analyzer.canApply(to: detuned, note: 39) && !analyzer.canApply(to: harmonic, note: 23))
        analyzer.invalidate(); precondition(analyzer.result == nil && analyzer.source == nil)
        let task = Task { await analyzer.analyze(changing) }
        while analyzer.source != ObjectIdentifier(changing.buffer) { await Task.yield() }
        analyzer.cancel()
        await analyzer.analyze(detuned)
        await task.value
        precondition(!analyzer.running)
        precondition(analyzer.result?.primary?.note == 69)
        print("PASS: local pitch sine/boundaries/detuning, missing fundamental/antiphase stereo, silence/noise/short/nonfinite, changing pitch, cancellation and stale source rejection")
    }
}
