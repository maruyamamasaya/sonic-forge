import Foundation
import AVFoundation

enum EnvelopeTests {
    static func run() {
        let parameters = ADSRParameters(attack: 0.1, decay: 0.2, sustain: 0.4, release: 0.3)
        var envelope = ADSREnvelope()
        envelope.trigger(parameters)
        for _ in 0..<50 { _ = envelope.next(sampleRate: 1000) }
        precondition(abs(envelope.level - 0.5) < 0.00001)
        for _ in 0..<50 { _ = envelope.next(sampleRate: 1000) }
        precondition(envelope.level == 1)
        for _ in 0..<200 { _ = envelope.next(sampleRate: 1000) }
        precondition(abs(envelope.level - 0.4) < 0.00001)
        envelope.noteOff()
        for _ in 0..<150 { _ = envelope.next(sampleRate: 1000) }
        precondition(abs(envelope.level - 0.2) < 0.00001)
        for _ in 0..<150 { _ = envelope.next(sampleRate: 1000) }
        precondition(envelope.stage == .idle && envelope.level == 0)
        envelope.trigger(parameters)
        for _ in 0..<40 { _ = envelope.next(sampleRate: 1000) }
        envelope.noteOff()
        let partial = envelope.next(sampleRate: 1000)
        precondition(partial > 0 && partial < 0.4)
        envelope.trigger(.legacy)
        precondition(envelope.next(sampleRate: 1000) == 1)
        envelope.noteOff()
        precondition(envelope.next(sampleRate: 1000) == 0)
        precondition(!ADSRParameters(attack: -1).isValid)
        precondition(!ADSRParameters(sustain: 2).isValid)
        precondition(!ADSRParameters(release: .infinity).isValid)

        // Test the production render callback on constant PCM: its output is
        // exactly the envelope, and both channels must receive the same gain.
        let format = AVAudioFormat(standardFormatWithSampleRate: 1000, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3000)!
        pcm.frameLength = 3000
        for i in 0..<3000 { pcm.floatChannelData![0][i] = 1; pcm.floatChannelData![1][i] = 0.5 }
        let sample = InstrumentSample(buffer: pcm, name: "constant", selection: AudioSelection(startFrame: 0, endFrame: 3000))
        let voice = InstrumentVoice()
        voice.install(sample)
        for rate in [0.5, 1.0, 2.0] {
            let frames = Int(100 * rate)
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            output.frameLength = AVAudioFrameCount(frames)
            voice.trigger(ADSRParameters(attack: 0.1, decay: 0, sustain: 1, release: 0.1), rate: rate)
            voice.render(frames: AVAudioFrameCount(frames), output: output.mutableAudioBufferList)
            precondition(abs(output.floatChannelData![0][frames - 1] - 1) < 0.00001)
            precondition(abs(output.floatChannelData![1][frames - 1] - 0.5) < 0.00001)
            let first = output.floatChannelData![0][0]
            precondition(abs(first - 1 / Float(frames)) < 0.00001)
            voice.release()
            voice.render(frames: AVAudioFrameCount(frames), output: output.mutableAudioBufferList)
            precondition(!voice.isActive)
            precondition(abs(output.floatChannelData![0][frames - 1]) < 0.00001)
        }
        voice.trigger(parameters, rate: 1)
        voice.stop()
        precondition(!voice.isActive)
        print("PASS: ADSR stages, mid-attack release, zero times, validation, stereo gain and pitch-independent timing in production render")
    }
}
