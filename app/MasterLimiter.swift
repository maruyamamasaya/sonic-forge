import AVFoundation
import AudioToolbox

struct MasterLimiter: Codable, Equatable {
    var enabled = false
    var ceilingDB = -1.0
    var releaseMS = 24.0
    static let off = MasterLimiter()
    static let standard = MasterLimiter(enabled: true)
    var isValid: Bool {
        ceilingDB.isFinite && (-12 ... -0.1).contains(ceilingDB) &&
            releaseMS.isFinite && (1...60).contains(releaseMS)
    }
}

/// Shared live/offline master path; the output meter sees the limited signal.
@MainActor
final class EnsembleMasterBus {
    let input = AVAudioMixerNode()
    private let limiter: AVAudioUnitEffect
    private let output: AVAudioMixerNode
    private var applied: MasterLimiter?
    init(engine: AVAudioEngine) {
        limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        output = engine.mainMixerNode
        engine.attach(input); engine.attach(limiter)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.connect(input, to: limiter, format: format)
        engine.connect(limiter, to: output, format: format)
        apply(.off, masterDB: -12)
    }
    func apply(_ settings: MasterLimiter, masterDB: Double) {
        let safe = settings.isValid ? settings : .off
        // Normalize the chosen ceiling to the unit's 0 dBFS limit, then restore it.
        let outputGain: Float = safe.enabled ? Float(pow(10, safe.ceilingDB / 20)) : 1
        // Lower the final gain before raising the pre-gain, avoiding a transient boost.
        if safe.enabled { output.outputVolume = min(output.outputVolume, outputGain) }
        if applied != safe {
            if applied?.enabled != safe.enabled { limiter.auAudioUnit.reset() }
            AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.012, 0)
            AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, Float(safe.releaseMS / 1000), 0)
            AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, Float(-safe.ceilingDB), 0)
            limiter.bypass = !safe.enabled
            applied = safe
        }
        output.outputVolume = outputGain
        input.outputVolume = Float(pow(10, max(-60, min(0, masterDB.isFinite ? masterDB : -60)) / 20)) / 4
    }
    func reset() { limiter.auAudioUnit.reset() }
}
