import Foundation

struct ADSRParameters: Codable, Equatable {
    var attack = 0.005
    var decay = 0.08
    var sustain = 0.8
    var release = 0.15
    static let standard = ADSRParameters()
    static let legacy = ADSRParameters(attack: 0, decay: 0, sustain: 1, release: 0)
    var isValid: Bool {
        [attack, decay, release].allSatisfy { $0.isFinite && (0...5).contains($0) }
            && sustain.isFinite && (0...1).contains(sustain)
    }
}

/// Linear, sample-clock envelope. The caller supplies the clock rate so stages
/// retain their wall-clock lengths even when the source is played at varispeed.
struct ADSREnvelope {
    enum Stage { case idle, attack, decay, sustain, release }
    private(set) var stage: Stage = .idle
    private(set) var level = 0.0
    private var parameters = ADSRParameters.standard
    private var elapsed = 0
    private var releaseLevel = 0.0
    mutating func trigger(_ parameters: ADSRParameters) {
        self.parameters = parameters
        elapsed = 0; level = 0; stage = .attack
    }
    mutating func noteOff() {
        guard stage != .idle && stage != .release else { return }
        releaseLevel = level; elapsed = 0; stage = .release
    }
    mutating func stop() { stage = .idle; level = 0; elapsed = 0 }
    mutating func next(sampleRate: Double) -> Float {
        // Zero-time stages advance without consuming an output sample.
        if stage == .attack && parameters.attack == 0 { stage = .decay; level = 1; elapsed = 0 }
        if stage == .decay && parameters.decay == 0 { stage = .sustain; level = parameters.sustain; elapsed = 0 }
        switch stage {
        case .idle: level = 0
        case .attack:
            elapsed += 1
            let count = max(1, Int((parameters.attack * sampleRate).rounded()))
            level = min(1, Double(elapsed) / Double(count))
            if elapsed >= count { stage = .decay; elapsed = 0 }
        case .decay:
            elapsed += 1
            let count = max(1, Int((parameters.decay * sampleRate).rounded()))
            level = 1 - (1 - parameters.sustain) * min(1, Double(elapsed) / Double(count))
            if elapsed >= count { stage = .sustain; elapsed = 0 }
        case .sustain: level = parameters.sustain
        case .release:
            if parameters.release == 0 { stop() }
            else {
                elapsed += 1
                let count = max(1, Int((parameters.release * sampleRate).rounded()))
                level = releaseLevel * max(0, 1 - Double(elapsed) / Double(count))
                if elapsed >= count { stop() }
            }
        }
        return Float(level)
    }
}
