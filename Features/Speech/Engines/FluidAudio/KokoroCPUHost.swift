import FluidAudio
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Kokoro 82M on the **ONNX CPU route**, Kokoro's default route.
///
/// - Synthesis: ONNX Runtime CPU execution provider (`KokoroONNXSession`,
///   `onnx-community/Kokoro-82M-v1.0-ONNX` fp16, 163 MB, downloaded by `KokoroONNXModelStore`).
///   No Core ML, Espresso or BNNS anywhere in the call → immune to the iOS 26.4+ libBNNS SIGSEGV,
///   and allowed in the background (CPU work while audio plays), so `rendersInBackground`.
/// - Text frontend: FluidAudio's English frontend rebuilt without Core ML
///   (`KokoroAneCPUFrontend`, a Reader patch in `Vendor/FluidAudio`): NeMo/regex normalizer,
///   Misaki lexicon, and a pure-Swift port of the BART G2P for out-of-vocabulary words. Same
///   phonemes, vocab (`ANE/vocab.json`) and voice packs (`ANE/<voice>.bin`) as the Core ML route,
///   so cached audio keeps its "kokoro.<voice>" key and all curated voices work.
/// - Style vector = voice-pack row `len(phonemes) − 1` (FluidAudio / kokoro-onnx rule); output ×0.69
///   to match the Core ML route's loudness (ONNX measured ≈3 dB louder).
/// - Threads: `KokoroRouteSettings.cpuThreads` (default: every core but one, 5 on an iPhone 17
///   Pro) while the app is in front, one in the
///   background (`KokoroRouteSettings.onnxThreads`). ORT fixes the count when a session is
///   created, so the first call after a phase change rebuilds the session at the other count
///   (`KokoroONNXSessionSlot`, ≈0.5 s on device; logged `kokoro_cpu_threads_switch`). Sessions are
///   created on a `.userInitiated` queue, so ORT's pool threads (spawned then) keep that QoS. Each
///   run is called from a queue of the call's `RenderPriority`: `.utility` for bake-ahead lowers
///   only the calling thread's share (ORT has no per-run thread QoS or count). One call at a time
///   (render gate).
/// - Memory: each run shrinks ORT's arena when it ends (`KokoroONNXSession`). A memory warning
///   lets go of the session (≈160 MB of weights plus the arena); the next call builds it again
///   (≈0.5 s), at the phase's thread count. Logged `kokoro_cpu_session_released`.
final class KokoroCPUHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .kokoro
    var onProgress: (@Sendable (Double) -> Void)?
    /// Threads while the app is in front (`KokoroRouteSettings.cpuThreads`).
    let threads: Int
    let sessionQoS: DispatchQoS.QoSClass = .userInitiated
    /// Read before each call: the background gets one thread.
    private let runState: AppRunState
    /// Calls above this many tokens are re-split by the renderer (`inputTooLong`). Chunks are
    /// ≤ 280 units (`TextChunker.Limits.kokoroCPU`, whole-paragraph profile, ≈1.0–1.3 tokens per char); this only catches
    /// phoneme-dense text (numbers, acronyms). Kokoro's own cap is 510 phonemes.
    /// Kokoro pads every call with ≈0.3 s + ≈0.5 s of silence; trim it at joins.
    var trimsEdgeSilence: Bool { true }
    func spokenText(forChunk text: String) -> String { KokoroSpokenText.closeOpenEnd(text) }
    static let maxTokensPerCall = 360
    static let gain = KokoroCPUAudio.coreMLMatchGain

    private let load = SingleFlightLoad()
    private let lock = NSLock()
    private var voice: String
    private var sessions: KokoroONNXSessionSlot<KokoroONNXSession>?
    private var frontend: KokoroAneCPUFrontend?
    private var packs: [String: [Float]] = [:]
    /// Where the ONNX crash count lives: a healthy stretch resets it (nil: the CPU bench's frontend-only host).
    private let crashCount: KokoroRouteSettings?
    private var healthyCalls = 0
    private var memoryWarning: NSObjectProtocol?

    var routingLabel: String? { "onnxCPU t\(lock.withLock { sessions }?.threads ?? threads)" }
    var rendersInBackground: Bool { true }
    var routeTag: String? { KokoroRoute.onnxCPU.rawValue }

    init(voice: String = KokoroHost.defaultVoice, threads: Int = KokoroRouteSettings.defaultThreads,
         crashCount: KokoroRouteSettings? = nil, runState: AppRunState = .shared) {
        self.voice = voice
        self.threads = threads
        self.crashCount = crashCount
        self.runState = runState
        #if canImport(UIKit)
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.releaseSession(reason: "memory_warning") }
        #endif
    }

    deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
    }

    /// Give the ONNX session's memory back and stay prepared: the next call builds it again.
    func releaseSession(reason: String) {
        guard let sessions = lock.withLock({ self.sessions }), sessions.release() else { return }
        ListenTimingLog.log("kokoro_cpu_session_released", ["reason": reason, "mem_mb": ProcessMemory.footprintMB])
    }

    /// Threads for a call now.
    private var phaseThreads: Int { KokoroRouteSettings.onnxThreads(configured: threads, phase: runState.phase) }

    func setVoice(_ voice: String) { lock.withLock { self.voice = voice } }
    private var currentVoice: String { lock.withLock { voice } }
    var isPrepared: Bool { load.isLoaded }

    func prepare() async throws {
        let progress = onProgress
        let voice = currentVoice
        let threads = phaseThreads
        let qos = self.sessionQoS
        try await load.run {
            let t0 = ListenTimingLog.now()
            let reused = KokoroONNXModelStore.fileLooksInstalled
            ListenTimingLog.log("kokoro_cpu_init_start", ["voice": voice, "threads": threads, "model_on_disk": reused])
            do {
                // 1) Small frontend files (vocab, G2P weights, lexicon ≈ 12 MB on a fresh install).
                progress?(0.01)
                try await KokoroAneCPUFrontend.ensureAssets()
                try await KokoroAssets.ensureVoicePack(voice)
                // 2) The 163 MB ONNX model.
                try await KokoroONNXModelStore.shared.ensureInstalled { f in progress?(0.03 + 0.97 * f) }
                try Task.checkCancellation()
                let tPrepared = ListenTimingLog.ms(since: t0)
                // 3) Load: lexicon + Swift G2P, voice pack, ORT session (on the render QoS).
                let fe = try KokoroAneCPUFrontend()
                try await fe.prepare()
                let pack = try KokoroAssets.loadVoicePack(voice)
                let tSession = ListenTimingLog.now()
                // NaN-safe model (patched once from the download; see KokoroONNXModelPatch).
                let model = try await KokoroONNXSession.onQueue(qos) { KokoroONNXModelStore.ensurePatchedModel() }
                let modelURL = model.url
                let sessions = KokoroONNXSessionSlot<KokoroONNXSession> { threads in
                    try await KokoroONNXSession.onQueue(qos) {
                        try KokoroONNXSession(modelURL: modelURL, threads: threads, allowSpinning: false)
                    }
                }
                try await sessions.load(threads: threads)
                self.lock.withLock {
                    self.frontend = fe
                    self.sessions = sessions
                    self.packs[voice] = pack
                }
                ListenTimingLog.log("kokoro_cpu_init_end", [
                    "ok": true, "ms": ListenTimingLog.ms(since: t0), "download_ms": tPrepared,
                    "session_ms": ListenTimingLog.ms(since: tSession), "threads": threads,
                    "reused_model": reused, "ort": KokoroONNXSession.runtimeVersion,
                    "nan_patched": model.patched, "patched_now": model.patchedNow,
                ])
            } catch {
                ListenTimingLog.log("kokoro_cpu_init_end", [
                    "ok": false, "ms": ListenTimingLog.ms(since: t0), "err": error.localizedDescription,
                ])
                throw error
            }
        }
    }

    /// After the load in flight (if any) has stopped, so it can't set a session again.
    func unload() async {
        await load.close()
        lock.withLock {
            sessions = nil
            frontend = nil
            packs.removeAll()
        }
    }

    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM {
        let (fe, sessions) = lock.withLock { (frontend, self.sessions) }
        let qos = priority.qos
        guard let fe, let sessions else { throw LocalSynthError.engineUnavailable("Kokoro (CPU) not loaded") }
        let voice = currentVoice
        let t0 = ListenTimingLog.now()
        let phonemes = try await fe.phonemes(for: text)
        let ids = try await fe.tokenIDs(for: phonemes)
        let g2pMs = ListenTimingLog.ms(since: t0)
        guard !ids.isEmpty else { throw LocalSynthError.emptyText }
        if ids.count > Self.maxTokensPerCall || phonemes.count > KokoroCPUTensorBuilder.maxPhonemes {
            throw LocalSynthError.inputTooLong("\(ids.count) tokens > \(Self.maxTokensPerCall) per CPU call")
        }
        let pack = try voicePack(voice)
        let inputs = try KokoroCPUTensorBuilder.build(tokenIDs: ids, phonemeCount: phonemes.count, voicePack: pack)
        let session = try await sessionForPhase(sessions)
        let tRun = ListenTimingLog.now()
        var raw = try await KokoroONNXSession.onQueue(qos) { try session.run(inputs) }
        var nanRetry = false
        if !KokoroCPUAudio.allFinite(raw) {
            // Should not happen with the patched model; never write NaN (it becomes a full-scale
            // pop + silence). Retry once at a 2 % different speed (different frame count / rounding),
            // then give up so the queue speaks this chunk with Apple instead of dead air.
            ListenTimingLog.log("onnx_nonfinite", ["chars": text.count, "tokens": ids.count, "retry": true])
            var retryInputs = inputs
            retryInputs.speed = [1.02]
            raw = try await KokoroONNXSession.onQueue(qos) { try session.run(retryInputs) }
            nanRetry = true
            guard KokoroCPUAudio.allFinite(raw) else {
                ListenTimingLog.log("onnx_nonfinite", ["chars": text.count, "tokens": ids.count, "retry": false])
                throw LocalSynthError.engineUnavailable("Kokoro ONNX produced invalid audio (NaN)")
            }
        }
        let onnxMs = ListenTimingLog.ms(since: tRun)
        let gain = Self.gain
        let samples = raw.map { $0 * gain }
        noteHealthyCall()
        return SynthesizedPCM(
            samples: samples,
            sampleRate: KokoroCPUAudio.sampleRate,
            metrics: [
                "phonemes": phonemes.count, "tokens": ids.count, "style_row": inputs.styleRow,
                "g2p_ms": g2pMs, "onnx_ms": onnxMs, "threads": session.threads, "nan_retry": nanRetry,
                "mem_mb": ProcessMemory.footprintMB,
            ]
        )
    }

    /// The session at the thread count of the app's phase now, rebuilt first after a phase change.
    /// A failed rebuild leaves the host unloaded: the next render loads it again.
    private func sessionForPhase(_ sessions: KokoroONNXSessionSlot<KokoroONNXSession>) async throws -> KokoroONNXSession {
        let wanted = phaseThreads
        let t0 = ListenTimingLog.now()
        let wasReleased = sessions.threads == nil
        do {
            let (session, rebuiltFrom) = try await sessions.session(threads: wanted)
            if wasReleased {
                ListenTimingLog.log("kokoro_cpu_session_rebuilt", [
                    "threads": wanted, "ms": ListenTimingLog.ms(since: t0), "mem_mb": ProcessMemory.footprintMB,
                ])
            }
            if let rebuiltFrom {
                // The head-start rule's pace was measured at the other thread count.
                RenderPace.shared.reset()
                ListenTimingLog.log("kokoro_cpu_threads_switch", [
                    "from": rebuiltFrom, "to": wanted, "phase": runState.phase.rawValue,
                    "ms": ListenTimingLog.ms(since: t0), "mem_mb": ProcessMemory.footprintMB,
                ])
            }
            return session
        } catch {
            ListenTimingLog.log("kokoro_cpu_threads_switch", ["to": wanted, "ok": false, "err": error.localizedDescription])
            load.reset()
            throw error
        }
    }

    private func voicePack(_ voice: String) throws -> [Float] {
        if let cached = lock.withLock({ packs[voice] }) { return cached }
        let pack = try KokoroAssets.loadVoicePack(voice)
        lock.withLock { packs[voice] = pack }
        return pack
    }

    /// After a healthy stretch, forget earlier ONNX-route crashes (the "two crashes → Apple" rule
    /// counts crashes close together, not over the app's lifetime).
    private func noteHealthyCall() {
        let reached: Bool = lock.withLock {
            healthyCalls += 1
            return healthyCalls == KokoroCrashRecovery.healthyRendersToReset
        }
        guard reached, let crashCount, crashCount.onnxCrashCount > 0 else { return }
        crashCount.onnxCrashCount = 0
        ListenTimingLog.log("kokoro_onnx_crash_count_reset", ["after_calls": KokoroCrashRecovery.healthyRendersToReset])
    }

    // MARK: - Files

    /// Prepare what the route needs for `voice` without loading it (the Core ML route's fallback).
    static func ensureFiles(voice: String) async throws {
        try await KokoroAneCPUFrontend.ensureAssets()
        try await KokoroAssets.ensureVoicePack(voice)
        try await KokoroONNXModelStore.shared.ensureInstalled()
    }

    /// Everything the CPU route needs is on disk (cheap checks, no hashing).
    static var filesLookInstalled: Bool {
        KokoroONNXModelStore.fileLooksInstalled && KokoroAneCPUFrontend.assetsPresent()
    }
}

#if DEBUG
/// The CPU route benchmark's frontend (no Core ML).
extension KokoroCPUHost: KokoroCPURouteFrontend {
    func cpuRoutePhonemes(for text: String) async throws -> String {
        let fe = try await loadedFrontend()
        return try await fe.phonemes(for: text)
    }

    func cpuRouteTokenIDs(for phonemes: String) async throws -> [Int32] {
        let fe = try await loadedFrontend()
        return try await fe.tokenIDs(for: phonemes)
    }

    func cpuRouteVoicePack(_ voice: String) async throws -> [Float] {
        try await KokoroAssets.ensureVoicePack(voice)
        return try voicePack(voice)
    }

    private func loadedFrontend() async throws -> KokoroAneCPUFrontend {
        if let fe = lock.withLock({ frontend }) { return fe }
        try await KokoroAneCPUFrontend.ensureAssets()
        let fe = try KokoroAneCPUFrontend()
        try await fe.prepare()
        lock.withLock { if frontend == nil { frontend = fe } }
        return lock.withLock { frontend ?? fe }
    }
}
#endif

/// Frontend-files presence check without importing FluidAudio at the call site.
enum KokoroAneCPUFrontendFiles {
    static var present: Bool { KokoroAneCPUFrontend.assetsPresent() }
}
