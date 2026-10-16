import AVFoundation
import Foundation

/// What `AppleFallbackRenderer` needs from a synthesizer (`AVSpeechSynthesizer`; a stub in tests).
protocol SpeechBufferWriting: AnyObject {
    func write(_ utterance: AVSpeechUtterance, toBufferCallback bufferCallback: @escaping AVSpeechSynthesizer.BufferCallback)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechBufferWriting {}

/// Renders text with Apple's synthesizer into an audio file: the fallback for text the on-device
/// engine can't produce (audio is never skipped silently), for the render queue and the listen
/// player alike. Always 1×, like every other unit: the player applies the listen speed.
///
/// Each render writes through a synthesizer of its own, so the queue's fallback and the player's
/// never wait on each other, and none outlives a media-services reset. A synthesizer that goes
/// quiet (no buffer for `idleTimeout`) is stopped and the render throws `TimedOut`: the caller
/// falls through as for any failure instead of waiting forever.
struct AppleFallbackRenderer: Sendable {
    struct TimedOut: LocalizedError {
        var errorDescription: String? { "Apple TTS stopped responding" }
    }

    var idleTimeout: Duration = .seconds(10)
    var makeSynthesizer: @Sendable () -> SpeechBufferWriting = { AVSpeechSynthesizer() }

    /// `voiceID`, else the system voice for `language`.
    func render(text: String, to destination: URL, voiceID: String?,
                language: String = "en-US") async throws -> TimeInterval {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: language)

        let synthesizer = makeSynthesizer()
        let file = FallbackFileWrite(destination: destination)
        let idleTimeout = self.idleTimeout
        return try await withCheckedThrowingContinuation { continuation in
            file.start(continuation)
            synthesizer.write(utterance) { file.receive($0) }
            // Holds the synthesizer until the write ends.
            Task {
                let tick = min(idleTimeout / 4, .milliseconds(250))
                while !file.isFinished {
                    try? await Task.sleep(for: tick)
                    if file.hasBeenIdle(for: idleTimeout) {
                        synthesizer.stopSpeaking(at: .immediate)
                        file.finish(.failure(TimedOut()))
                    }
                }
            }
        }
    }
}

/// One render's file and result. Buffers arrive on the synthesizer's queue, the idle check on
/// another: the lock orders them, and the first result wins.
private final class FallbackFileWrite: @unchecked Sendable {
    private let destination: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TimeInterval, Error>?
    /// One file across callbacks: `write(_:)` delivers many buffers for anything longer than a
    /// few words, and each is appended to it.
    private var file: AVAudioFile?
    private var frames: AVAudioFrameCount = 0
    private var sampleRate: Double = 22050
    private var lastBuffer = ContinuousClock.now
    private var finished = false

    init(destination: URL) {
        self.destination = destination
    }

    var isFinished: Bool { lock.withLock { finished } }

    func start(_ continuation: CheckedContinuation<TimeInterval, Error>) {
        lock.withLock {
            self.continuation = continuation
            lastBuffer = .now
        }
    }

    func hasBeenIdle(for timeout: Duration) -> Bool {
        lock.withLock { !finished && ContinuousClock.now - lastBuffer >= timeout }
    }

    func receive(_ buffer: AVAudioBuffer) {
        lock.lock()
        lastBuffer = .now
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            lock.unlock()
            finish(.success(0.05))
            return
        }
        if pcm.frameLength == 0 {
            let duration = sampleRate > 0 ? Double(frames) / sampleRate : 0.05
            let result: Result<TimeInterval, Error> = frames > 0
                ? .success(max(duration, 0.05))
                : .failure(NSError(domain: "AppleFallbackRenderer", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "Apple TTS produced no audio"]))
            lock.unlock()
            finish(result)
            return
        }
        sampleRate = pcm.format.sampleRate
        frames += pcm.frameLength
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: destination, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            lock.unlock()
        } catch {
            lock.unlock()
            finish(.failure(error))
        }
    }

    func finish(_ result: Result<TimeInterval, Error>) {
        let continuation: CheckedContinuation<TimeInterval, Error>? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            file = nil // closes it
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}
