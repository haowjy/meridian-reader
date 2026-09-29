import AVFoundation
import Foundation

/// Renders text with AVSpeechSynthesizer.write into a PCM file. Used as the Apple-TTS
/// fallback for a local-engine chunk that cannot be synthesized (never silently skip audio).
final class ProbePCMRenderer: NSObject, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    func render(
        text: String,
        to destination: URL,
        rate: Float,
        voiceID: String?,
        language: String
    ) async throws -> TimeInterval {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TimeInterval, Error>) in
            var resumed = false
            var totalFrames: AVAudioFrameCount = 0
            var sampleRate: Double = 22050
            // Keep ONE file open across callbacks — write(_:) delivers many buffers for
            // anything longer than a few words (the old version recreated the file per buffer
            // and kept only the last one).
            var file: AVAudioFile?

            func finish(_ result: Result<TimeInterval, Error>) {
                guard !resumed else { return }
                resumed = true
                file = nil // closes
                cont.resume(with: result)
            }

            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    finish(.success(0.05))
                    return
                }
                if pcm.frameLength == 0 {
                    let duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0.05
                    finish(totalFrames > 0 ? .success(max(duration, 0.05)) : .failure(NSError(
                        domain: "ProbePCMRenderer", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Apple TTS produced no audio"])))
                    return
                }
                sampleRate = pcm.format.sampleRate
                totalFrames += pcm.frameLength
                do {
                    if file == nil {
                        file = try AVAudioFile(
                            forWriting: destination, settings: pcm.format.settings,
                            commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }
}
