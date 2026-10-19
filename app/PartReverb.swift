import AVFoundation

/// One fixed room keeps the amount control predictable across live and offline audio.
enum PartReverb {
    static func isValid(_ amount: Double) -> Bool { amount.isFinite && (0...100).contains(amount) }
    static func tailSeconds(_ amount: Double) -> Double { amount > 0 ? 3 : 0 }
    static func makeNode() -> AVAudioUnitReverb {
        let node = AVAudioUnitReverb()
        node.loadFactoryPreset(.smallRoom)
        node.wetDryMix = 0; node.bypass = true
        return node
    }
}
