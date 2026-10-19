import AVFoundation
import AudioToolbox

/// Apple's dynamics processor uses headroom rather than a fixed compression ratio.
struct PartCompressor: Codable, Equatable {
    var enabled = false
    var thresholdDB = -24.0
    var headroomDB = 5.0
    var attackMS = 10.0
    var releaseMS = 150.0
    var makeupDB = 0.0
    static let off = PartCompressor()
    var isValid: Bool {
        thresholdDB.isFinite && (-40...0).contains(thresholdDB) &&
        headroomDB.isFinite && (0.1...40).contains(headroomDB) &&
        attackMS.isFinite && (0.1...200).contains(attackMS) &&
        releaseMS.isFinite && (10...3000).contains(releaseMS) &&
        makeupDB.isFinite && (0...24).contains(makeupDB)
    }
    func apply(to node: AVAudioUnitEffect) {
        let value = isValid ? self : .off
        let parameters: [(AudioUnitParameterID, Double)] = [
            (kDynamicsProcessorParam_Threshold, value.thresholdDB),
            (kDynamicsProcessorParam_HeadRoom, value.headroomDB),
            (kDynamicsProcessorParam_AttackTime, value.attackMS / 1000),
            (kDynamicsProcessorParam_ReleaseTime, value.releaseMS / 1000),
            (kDynamicsProcessorParam_OverallGain, value.makeupDB),
            (kDynamicsProcessorParam_ExpansionRatio, 1),
            (kDynamicsProcessorParam_ExpansionThreshold, -80)
        ]
        for (key, amount) in parameters {
            AudioUnitSetParameter(node.audioUnit, key, kAudioUnitScope_Global, 0, Float(amount), 0)
        }
        node.bypass = !value.enabled
    }
    static func makeNode() -> AVAudioUnitEffect {
        let node = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        off.apply(to: node)
        return node
    }
}
