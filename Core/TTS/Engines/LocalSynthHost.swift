import AVFoundation
import Foundation

/// One synthesized model call.
struct SynthesizedPCM: @unchecked Sendable {
    var samples: [Float]
    var sampleRate: Int
    /// Engine-specific timing-log fields (phonemes, frames, stage ms, …).
    var metrics: [String: Any] = [:]

    var duration: TimeInterval { sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0 }
}

/// Errors a host maps its library's errors onto so the shared renderer can react.
enum LocalSynthError: LocalizedError {
    /// Input exceeded the engine's per-call cap (tokens / phonemes / audio length). The shared
    /// `LocalChunkRenderer` re-splits the text and retries.
    case inputTooLong(String)
    case emptyText
    case engineUnavailable(String)
    /// The app is in the background and the active host can't render there (Core ML: GPU
    /// forbidden, CPU paths hit the libBNNS crash on iOS 26.4+). Callers fall back to Apple TTS or
    /// defer. Hosts with `rendersInBackground` (ONNX CPU) never see this.
    case deferredInBackground

    var errorDescription: String? {
        switch self {
        case .inputTooLong(let detail): return detail
        case .emptyText: return "Nothing to synthesize."
        case .engineUnavailable(let detail): return detail
        case .deferredInBackground: return "On-device voice paused while Meridian Reader is in the background."
        }
    }
}

/// How soon a synth call's audio is needed. Hosts that run on the CPU map it onto the QoS of
/// their compute queue.
enum RenderPriority: Sendable {
    /// Someone is listening to the article: they wait on this chunk or will play it shortly.
    case listener
    /// Rendering ahead (e.g. a saved article) — nobody waits; may run slower and cooler.
    case bakeAhead

    var qos: DispatchQoS.QoSClass { self == .listener ? .userInitiated : .utility }
    var taskPriority: TaskPriority { self == .listener ? .userInitiated : .utility }
}

/// One on-device synth backend behind `LocalSynthService` (built by a
/// `SpeechEngineProvider`). Hosts are thin: load models, run ONE call, map overflow errors to
/// `LocalSynthError.inputTooLong`. Chunking, re-split, the render gate, crash guard, timing log
/// and CAF writing are shared (`LocalChunkRenderer`). Exactly one host is alive at a time.
protocol LocalSynthHost: AnyObject, Sendable {
    var engineID: SpeechEngineID { get }
    /// Compute routing actually used (for logs / probe), nil if not applicable.
    var routingLabel: String? { get }
    /// Download progress (0…1) while models are fetched; may be called off-main.
    var onProgress: (@Sendable (Double) -> Void)? { get set }
    var isPrepared: Bool { get }
    /// Download (if needed) and load models. Single-flight (`SingleFlightLoad`); cancelling the
    /// caller cancels the load. Implementations must hold `SynthRenderGate.shared` while loading
    /// Core ML models.
    func prepare() async throws
    /// ONE model call for already-sized text. The caller holds the render gate.
    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM
    /// Switch voice (no-op for single-voice engines).
    func setVoice(_ voice: String)
    /// Release the models for good, once a load in flight has stopped (it can't set them again).
    /// An unloaded host isn't used again: `LocalSynthService` builds a new one.
    func unload() async
    /// May this host start a model call while the app is in the background? Only hosts that
    /// never touch Core ML/GPU (Kokoro's ONNX CPU route) say yes. Default: no.
    var rendersInBackground: Bool { get }
    /// Short route tag for crash markers / logs ("onnx", "coreml"; nil = n/a).
    var routeTag: String? { get }
    /// Trim each chunk's leading/trailing silence to boundary-sized pauses (`ChunkEdgeTrim`).
    var trimsEdgeSilence: Bool { get }
}

extension LocalSynthHost {
    var rendersInBackground: Bool { false }
    var routeTag: String? { nil }
    var trimsEdgeSilence: Bool { false }
}

/// The one CAF writer for rendered audio (mono Int16): every chunk a host renders
/// (`LocalChunkRenderer`) and every stitched paragraph (`ChunkAudioStitcher`).
enum LocalPCMWriter {
    enum WriteError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .failed(let detail): return "Failed to write PCM: \(detail)"
            }
        }
    }

    static func write(_ samples: [Float], sampleRate: Int, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        )
        guard let format else {
            throw LocalPCMWriter.WriteError.failed("Could not build Int16 mono format @ \(sampleRate) Hz")
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1)) else {
            throw LocalPCMWriter.WriteError.failed("Could not allocate PCM buffer (\(samples.count) frames)")
        }
        buffer.frameLength = frameCount

        guard let channels = buffer.int16ChannelData else {
            throw LocalPCMWriter.WriteError.failed("int16ChannelData unavailable")
        }
        let channel = channels[0]
        for i in 0..<samples.count {
            // NaN/inf must never reach the file: `min(1, NaN)` is 1 → a full-scale DC block
            // (a loud pop, silence, a pop). The unpatched Kokoro ONNX model emits NaN.
            let v = samples[i]
            let clamped = v.isFinite ? max(-1.0, min(1.0, v)) : 0
            channel[i] = Int16(clamped * Float(Int16.max))
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        // processingFormat must match the buffer (Int16 interleaved); the default init uses
        // Float32 deinterleaved and ExtAudioFile asserts (SIGTRAP) on the mismatch.
        let file = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try file.write(from: buffer)
    }

    /// Seconds of audio in the file at `url` (any format `AVAudioFile` reads); 0 when it can't be
    /// read. The one duration reader: blocking file I/O, so the player reads each unit's length
    /// once, off the main actor, and carries it with the unit.
    nonisolated static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
