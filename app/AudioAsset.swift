import Foundation
import AVFoundation

struct AudioAsset {
    let url: URL
    let duration: Double
    let sampleRate: Double
    let channels: Int
    let bitDepth: Int
    let byteCount: Int64
    let peaks: [[Float]]
    let isDemo: Bool

    static func load(_ url: URL, isDemo: Bool = false) throws -> AudioAsset {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1024 * 1024 else { throw AudioError.invalid("初期版では256 MB以下のWAVを読み込めます。") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12,
              String(data: header.prefix(4), encoding: .ascii) == "RIFF",
              String(data: header.suffix(4), encoding: .ascii) == "WAVE" else {
            throw AudioError.invalid("対応するWAVファイルではありません。PCMまたはFloat形式のWAVを選んでください。")
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard file.length > 0, format.sampleRate > 0, (1...2).contains(channels) else {
            throw AudioError.invalid("空の音源や3チャンネル以上の音源にはまだ対応していません。")
        }
        let count = min(115200, Int(file.length))
        var peaks = Array(repeating: Array(repeating: Float(0), count: count), count: channels)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384) else {
            throw AudioError.invalid("波形の読み込みに必要なメモリを確保できませんでした。")
        }
        var offset: Int64 = 0
        while offset < file.length {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(16384, file.length - offset)))
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else {
                throw AudioError.invalid("音源データを最後まで読み込めませんでした。")
            }
            for frame in 0..<Int(buffer.frameLength) {
                let bucket = min(count - 1, Int((offset + Int64(frame)) * Int64(count) / file.length))
                for channel in 0..<channels {
                    let value = data[channel][frame]
                    if value.isFinite { peaks[channel][bucket] = max(peaks[channel][bucket], abs(value)) }
                }
            }
            offset += Int64(buffer.frameLength)
        }
        return AudioAsset(url: url, duration: Double(file.length) / format.sampleRate,
                          sampleRate: format.sampleRate, channels: channels,
                          bitDepth: file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 0,
                          byteCount: Int64(size), peaks: peaks, isDemo: isDemo)
    }
}

enum AudioError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

enum DemoAudio {
    // Deterministic synthesis, no downloaded or copyrighted recording.
    static func write(to url: URL) throws {
        let rate = 48000, frames = rate * 8
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func word<T: FixedWidthInteger>(_ n: T) {
            var value = n.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        text("RIFF"); word(UInt32(36 + frames * 4)); text("WAVEfmt ")
        word(UInt32(16)); word(UInt16(1)); word(UInt16(2)); word(UInt32(rate))
        word(UInt32(rate * 4)); word(UInt16(4)); word(UInt16(16)); text("data"); word(UInt32(frames * 4))
        var noise: UInt32 = 12345
        for i in 0..<frames {
            let t = Double(i) / Double(rate)
            noise = 1664525 &* noise &+ 1013904223
            let n = Double(noise) / Double(UInt32.max) * 2 - 1
            let attack = min(1, t / 0.005)
            let tail = min(1, (8 - t) / 0.05)
            for channel in 0..<2 {
                let phase = Double(channel) * 0.13
                let tone = sin(2 * .pi * 220 * t + phase) * exp(-t * 1.1)
                    + 0.45 * sin(2 * .pi * 523.25 * t + phase) * exp(-t * 1.8)
                    + 0.2 * sin(2 * .pi * 1174.66 * t) * exp(-t * 2.8)
                let sample = (tone * 0.38 + n * 0.08 * exp(-t * 7)) * attack * tail
                word(Int16(max(-1, min(1, sample)) * 32767))
            }
        }
        try data.write(to: url, options: .atomic)
    }
}

func timeLabel(_ seconds: Double) -> String {
    let milliseconds = Int(max(0, seconds) * 1000)
    return String(format: "%02d:%02d.%03d", milliseconds / 60000, milliseconds / 1000 % 60, milliseconds % 1000)
}
