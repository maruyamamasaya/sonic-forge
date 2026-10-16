import Foundation
import AVFoundation

/// Render only the selected frames, so playback cannot bleed past the selection.
/// UI timing is not used to gate audio. Float32 CAF preserves decoded samples.
enum SelectionAudio {
    static func write(source: URL, selection: AudioSelection, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard selection.startFrame >= 0, selection.endFrame <= input.length, selection.frameCount > 0 else {
            throw AudioError.invalid("選択範囲が音源の範囲外です。もう一度範囲を選択してください。")
        }
        var settings = input.processingFormat.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let output = try AVAudioFile(forWriting: destination, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16384) else {
            throw AudioError.invalid("選択範囲の再生を準備できませんでした。")
        }
        input.framePosition = selection.startFrame
        var remaining = selection.frameCount
        while remaining > 0 {
            try input.read(into: buffer, frameCount: AVAudioFrameCount(min(16384, remaining)))
            guard buffer.frameLength > 0 else { throw AudioError.invalid("選択範囲を最後まで読み込めませんでした。") }
            try output.write(from: buffer)
            remaining -= Int64(buffer.frameLength)
        }
    }
}
