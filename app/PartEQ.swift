import AVFoundation

/// Fixed tone controls in dB; the same settings feed live and offline rendering.
struct PartEQ: Codable, Equatable {
    var lowDB = 0.0
    var midDB = 0.0
    var highDB = 0.0
    static let flat = PartEQ()
    var isValid: Bool { [lowDB, midDB, highDB].allSatisfy { $0.isFinite && (-12...12).contains($0) } }
    func apply(to node: AVAudioUnitEQ) {
        let values = [lowDB, midDB, highDB]
        for (band, gain) in zip(node.bands, values) {
            let safe = gain.isFinite ? max(-12, min(12, gain)) : 0
            band.gain = Float(safe); band.bypass = safe == 0
        }
    }
    static func makeNode() -> AVAudioUnitEQ {
        let node = AVAudioUnitEQ(numberOfBands: 3)
        node.bands[0].filterType = .lowShelf; node.bands[0].frequency = 200
        node.bands[1].filterType = .parametric; node.bands[1].frequency = 1000; node.bands[1].bandwidth = 1
        node.bands[2].filterType = .highShelf; node.bands[2].frequency = 4000
        flat.apply(to: node)
        return node
    }
}
