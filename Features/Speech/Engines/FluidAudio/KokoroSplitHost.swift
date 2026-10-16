import Foundation

/// Kokoro's **Core ML route** (debug opt-in, `KokoroRoute.coreMLGPU`): Core ML (`KokoroHost`,
/// `aneTailGpu`) while the app is in front, ONNX CPU (`KokoroCPUHost`) from the first call made in
/// the background until the process ends.
///
/// Core ML can't run in the background (no GPU there, and its CPU path is the iOS 26.4+ libBNNS
/// crash), so the first background call falls back: the Core ML models are released and the ONNX
/// host loads. It stays on ONNX after the app comes back to the front, so locking and unlocking
/// never reloads Core ML. A crash in either route turns the whole route off at the next launch
/// (`KokoroCrashRecovery`).
///
/// `prepare()` loads Core ML and puts the ONNX files on disk (download only), so the fallback
/// never downloads in the background.
final class KokoroSplitHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .kokoro

    private let coreML: KokoroHost
    private let onnx: KokoroCPUHost
    private let runState: AppRunState
    private let lock = NSLock()
    private var onONNX = false

    init(coreML: KokoroHost, onnx: KokoroCPUHost, runState: AppRunState = .shared) {
        self.coreML = coreML
        self.onnx = onnx
        self.runState = runState
    }

    /// The host the next call goes to: ONNX once the app has been seen in the background.
    private var usesONNX: Bool { lock.withLock { onONNX } || runState.phase == .background }

    var routingLabel: String? { usesONNX ? onnx.routingLabel : coreML.routingLabel }
    /// Read by the crash guard right before each call, so a crash names the route that ran.
    var routeTag: String? { usesONNX ? KokoroRoute.onnxCPU.rawValue : KokoroRoute.coreMLGPU.rawValue }
    var rendersInBackground: Bool { true }
    /// Only the ONNX output carries Kokoro's padding as a separate trim; the Core ML route's
    /// chunks have always joined untrimmed. Read after the call that made the chunk.
    var trimsEdgeSilence: Bool { lock.withLock { onONNX } }

    var onProgress: (@Sendable (Double) -> Void)? {
        get { coreML.onProgress }
        set { coreML.onProgress = newValue }
    }

    var isPrepared: Bool { usesONNX ? onnx.isPrepared : coreML.isPrepared }

    func prepare() async throws {
        // Never load Core ML in the background.
        if runState.phase == .background { await fallBackToONNX() }
        if lock.withLock({ onONNX }) { return try await onnx.prepare() }
        try await coreML.prepare()
        try await KokoroCPUHost.ensureFiles(voice: coreML.currentVoice)
    }

    func setVoice(_ voice: String) {
        coreML.setVoice(voice)
        onnx.setVoice(voice)
    }

    func unload() async {
        await coreML.unload()
        await onnx.unload()
    }

    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM {
        if runState.phase == .background { await fallBackToONNX() }
        guard lock.withLock({ onONNX }) else {
            return try await coreML.synthesizeOnce(text: text, priority: priority)
        }
        // The caller holds the render gate; the ONNX load needs no Core ML and takes no gate.
        if !onnx.isPrepared { try await onnx.prepare() }
        return try await onnx.synthesizeOnce(text: text, priority: priority)
    }

    /// The first background load or call: release Core ML, render on ONNX from now on.
    private func fallBackToONNX() async {
        let first: Bool = lock.withLock {
            defer { onONNX = true }
            return !onONNX
        }
        guard first else { return }
        await coreML.unload()
        ListenTimingLog.log("kokoro_split_fallback", ["to": KokoroRoute.onnxCPU.rawValue, "reason": "background"])
    }
}
