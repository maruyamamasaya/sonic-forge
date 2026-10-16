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
        for velocity in [1, 32, 64, 127] {
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
            output.frameLength = 32
            voice.trigger(.legacy, rate: 1, velocity: velocity)
            voice.render(frames: 32, output: output.mutableAudioBufferList)
            precondition(abs(output.floatChannelData![0][31] - Float(velocity) / 127) < 0.00001)
            precondition(abs(output.floatChannelData![1][31] - Float(velocity) / 254) < 0.00001)
        }
        print("PASS: velocity scales both channels independently of envelope")
        voice.trigger(parameters, rate: 1)
        voice.stop()
        precondition(!voice.isActive)
        // Exact wrap sequence across render blocks, stereo, and release beyond EOF.
        for i in 0..<3000 { pcm.floatChannelData![0][i] = Float(i + 1); pcm.floatChannelData![1][i] = -Float(i + 1) }
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4000)!
        output.frameLength = 4000
        voice.trigger(ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.1), rate: 1,
                      loop: SampleLoop(enabled: true, startFrame: 2, endFrame: 5))
        for block in 0..<2 {
            voice.render(frames: 4000, output: output.mutableAudioBufferList)
            for i in 0..<4000 {
                let cursor = block * 4000 + i
                let expected = Float((cursor < 5 ? cursor : 2 + (cursor - 5) % 3) + 1)
                precondition(output.floatChannelData![0][i] == expected)
                precondition(output.floatChannelData![1][i] == -expected)
            }
            precondition(voice.isActive)
        }
        voice.release()
        voice.render(frames: 4000, output: output.mutableAudioBufferList)
        precondition(output.floatChannelData![0][0] > 0 && !voice.isActive)
        precondition(output.floatChannelData![0][100] == 0)
        voice.trigger(.legacy, rate: 1)
        voice.render(frames: 4000, output: output.mutableAudioBufferList)
        precondition(!voice.isActive && output.floatChannelData![0][3000] == 0)
        precondition(!SampleLoop(enabled: true, startFrame: 4, endFrame: 4).isValid(frameCount: 3000))
        precondition(!SampleLoop(enabled: true, startFrame: 0, endFrame: Int64.min).isValid(frameCount: 3000))
        // A deliberately discontinuous stereo ramp exposes the boundary jump.
        for i in 0..<3000 { pcm.floatChannelData![0][i] = Float(i % 100) / 50 - 1; pcm.floatChannelData![1][i] = -pcm.floatChannelData![0][i] }
        for rate in [0.5, 1.0, 2.0] {
            voice.trigger(ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0.1), rate: rate,
                          loop: SampleLoop(enabled: true, startFrame: 0, endFrame: 100, crossfadeFrames: 25))
            var last: Float = -1
            var maximum: Float = 0
            for _ in 0..<3 {
                voice.render(frames: 4000, output: output.mutableAudioBufferList)
                for i in 0..<4000 {
                    let value = output.floatChannelData![0][i]
                    maximum = max(maximum, abs(value - last)); last = value
                    precondition(abs(value) <= 1 && output.floatChannelData![1][i] == -value)
                }
            }
            precondition(maximum < 0.1) // OFF produces a 1.98 step.
            voice.release()
            voice.render(frames: 4000, output: output.mutableAudioBufferList)
            precondition(!voice.isActive)
        }
        precondition(!SampleLoop(endFrame: 100, crossfadeFrames: -1).isValid(frameCount: 100))
        precondition(!SampleLoop(endFrame: 100, crossfadeFrames: 51).isValid(frameCount: 100))
        print("PASS: crossfade reduces discontinuity below 0.1 (OFF 1.98), stereo, block continuity, pitched Release")
        print("PASS: loop exact wrap across blocks, stereo, hold beyond EOF, release and disabled EOF")
        print("PASS: ADSR stages, mid-attack release, zero times, validation, stereo gain and pitch-independent timing in production render")
    }
}
