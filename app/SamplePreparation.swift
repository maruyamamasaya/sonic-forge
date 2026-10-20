import Foundation

struct SamplePreparationSettings: Equatable {
    var normalize = true
    var targetDB = -3.0
    var fadeInMS = 5.0
    var fadeOutMS = 20.0
    var isValid: Bool {
        targetDB.isFinite && (-12 ... -0.1).contains(targetDB) &&
        fadeInMS.isFinite && (0 ... 250).contains(fadeInMS) &&
        fadeOutMS.isFinite && (0 ... 250).contains(fadeOutMS)
    }
}

struct PreparedSamplePCM {
    let channels: [[Float]]
    let originalPeak: Float
    let resultPeak: Float
    let gainDB: Double
    let boostLimited: Bool
}

/// Offline, linked-channel peak normalization and linear edge fades. Original PCM is immutable.
enum SamplePreparationProcessor {
    static func process(_ channels: [[Float]], sampleRate: Double, settings: SamplePreparationSettings) throws -> PreparedSamplePCM {
        guard settings.isValid, sampleRate.isFinite, (8000 ... 192000).contains(sampleRate),
              (1...2).contains(channels.count), let count = channels.first?.count, count > 0,
              Double(count) / sampleRate <= 30, channels.allSatisfy({ $0.count == count }),
              count * channels.count <= 16 * 1024 * 1024 else { throw invalid("加工する音源や設定が無効です。") }
        var peak: Float = 0
        for channel in channels {
            try Task.checkCancellation()
            for x in channel {
                guard x.isFinite else { throw invalid("音源に無効なサンプルがあります。") }
                peak = max(peak, abs(x))
            }
        }
        let requested = settings.normalize && peak > 0 ? pow(10, settings.targetDB / 20) / Double(peak) : 1
        let gain = min(requested, pow(10, 24.0 / 20))
        let fadeIn = min(count, Int((settings.fadeInMS * sampleRate / 1000).rounded()))
        let fadeOut = min(count, Int((settings.fadeOutMS * sampleRate / 1000).rounded()))
        var result = channels
        var resultPeak: Float = 0
        for channel in result.indices {
            for i in 0..<count {
                if i % 16384 == 0 { try Task.checkCancellation() }
                let attack = fadeIn > 1 && i < fadeIn ? Double(i) / Double(fadeIn-1) : 1
                let release = fadeOut > 1 && i >= count-fadeOut ? Double(count-1-i) / Double(fadeOut-1) : 1
                let x = Float(Double(channels[channel][i]) * gain * attack * release)
                guard x.isFinite else { throw invalid("加工結果が無効です。") }
                result[channel][i] = x
                resultPeak = max(resultPeak, abs(x))
            }
        }
        return PreparedSamplePCM(channels: result, originalPeak: peak, resultPeak: resultPeak,
                                 gainDB: 20 * log10(gain), boostLimited: gain < requested)
    }
    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "SonicForge.SamplePreparation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
