import AVFoundation

struct PartDelay: Codable, Equatable {
    var timeMS = 300.0
    var mix = 0.0
    var feedback = 35.0
    static let off = PartDelay()
    var isValid: Bool {
        timeMS.isFinite && (50...1000).contains(timeMS) && mix.isFinite && (0...100).contains(mix) &&
            feedback.isFinite && (0...60).contains(feedback)
    }
    /// Include the first echo and enough repeats to fall below -60 dB amplitude.
    var tailSeconds: Double {
        guard isValid, mix > 0 else { return 0 }
        let repeats = feedback == 0 ? 1 : 1 + ceil(log(0.001) / log(feedback / 100))
        return timeMS / 1000 * repeats
    }
    func apply(to node: AVAudioUnitDelay) {
        let settings = isValid ? self : .off
        node.delayTime = settings.timeMS / 1000
        node.feedback = Float(settings.feedback)
        node.wetDryMix = Float(settings.mix)
        node.bypass = settings.mix == 0
    }
    static func makeNode() -> AVAudioUnitDelay {
        let node = AVAudioUnitDelay()
        node.lowPassCutoff = 20000
        off.apply(to: node)
        return node
    }
}
