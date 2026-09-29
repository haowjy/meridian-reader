import FluidAudio
import Foundation

/// Kokoro 82M on the **ONNX CPU route** — Kokoro's main route since 2026-09-24.
///
/// - Synthesis: ONNX Runtime CPU execution provider (`KokoroONNXSession`,
///   `onnx-community/Kokoro-82M-v1.0-ONNX` fp16, 163 MB, downloaded by `CPURouteModelStore`).
///   No Core ML, Espresso or BNNS anywhere in the call → immune to the iOS 26.4+ libBNNS SIGSEGV,
///   and allowed in the background (CPU work while audio plays), so `rendersInBackground`.
/// - Text frontend: FluidAudio's English frontend rebuilt without Core ML
///   (`KokoroAneCPUFrontend`, a Reader patch in `Vendor/FluidAudio`): NeMo/regex normalizer,
///   Misaki lexicon, and a pure-Swift port of the BART G2P for out-of-vocabulary words. Same
///   phonemes, vocab (`ANE/vocab.json`) and voice packs (`ANE/<voice>.bin`) as the Core ML route,
///   so cached audio keeps its "kokoro.<voice>" key and all curated voices work.
/// - Style vector = voice-pack row `len(phonemes) − 1` (FluidAudio / kokoro-onnx rule); output ×0.69
///   to match the Core ML route's loudness (ONNX measured ≈3 dB louder).
/// - Threads: `KokoroRouteSettings.cpuThreads` (default 3); the session and every run live on a
///   `.userInitiated` queue so ORT's pool inherits that QoS. One call at a time (render gate).
final class KokoroCPUHost: LocalSynthHost, KokoroCPURouteFrontend, @unchecked Sendable {
    let engineID: SpeechEngineID = .kokoro
    var onProgress: (@Sendable (Double) -> Void)?
    let threads: Int
    let qos: DispatchQoS.QoSClass = .userInitiated
    /// Calls above this many tokens are re-split by the renderer (`inputTooLong`). Chunks are
    /// ≤ 280 units (`TextChunker.Limits.kokoroCPU`, ≈1.0–1.3 tokens per char); this only catches
    /// phoneme-dense text (numbers, acronyms). Kokoro's own cap is 510 phonemes.
    /// Kokoro pads every call with ≈0.3 s + ≈0.5 s of silence; trim it at joins.
    var trimsEdgeSilence: Bool { true }
    static let maxTokensPerCall = 360
    static let gain = KokoroCPUAudio.coreMLMatchGain

    private let lock = NSLock()
    private var didPrepare = false
    private var prepareTask: Task<Void, Error>?
    private var voice: String
    private var session: KokoroONNXSession?
    private var frontend: KokoroAneCPUFrontend?
    private var packs: [String: [Float]] = [:]
    private static let healthLock = NSLock()
    private static var healthyCalls = 0

    var routingLabel: String? { "onnxCPU·t\(threads)" }
    var rendersInBackground: Bool { true }
    var routeTag: String? { KokoroRoute.onnxCPU.rawValue }

    init(voice: String = KokoroHost.defaultVoice, threads: Int = KokoroRouteSettings().cpuThreads) {
        self.voice = voice
        self.threads = threads
    }

    func setVoice(_ voice: String) { lock.withLock { self.voice = voice } }
    private var currentVoice: String { lock.withLock { voice } }
    var isPrepared: Bool { lock.withLock { didPrepare } }

    func prepare() async throws {
        let task: Task<Void, Error>? = lock.withLock {
            if didPrepare { return nil }
            if let existing = prepareTask { return existing }
            let created = makePrepareTask()
            prepareTask = created
            return created
        }
        guard let task else { return }
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            lock.withLock { didPrepare = true; prepareTask = nil }
        } catch {
            lock.withLock { didPrepare = false; prepareTask = nil }
            throw error
        }
    }

    /// Called with `lock` held.
    private func makePrepareTask() -> Task<Void, Error> {
        let progress = onProgress
        let voice = self.voice
        let threads = self.threads
        let qos = self.qos
        return Task {
            let t0 = ListenTimingLog.now()
            let reused = CPURouteModelStore.fileLooksInstalled
            ListenTimingLog.log("kokoro_cpu_init_start", ["voice": voice, "threads": threads, "model_on_disk": reused])
            do {
                // 1) Small frontend files (vocab, G2P weights, lexicon ≈ 12 MB on a fresh install).
                progress?(0.01)
                try await KokoroAneCPUFrontend.ensureAssets()
                try await Self.ensureVoicePackFile(voice)
                // 2) The 163 MB ONNX model (reuses the debug benchmark's file if present).
                try await CPURouteModelStore.shared.ensureInstalled { f in progress?(0.03 + 0.97 * f) }
                try Task.checkCancellation()
                let tDownloaded = ListenTimingLog.ms(since: t0)
                // 3) Load: lexicon + Swift G2P, voice pack, ORT session (on the render QoS).
                let fe = try KokoroAneCPUFrontend()
                try await fe.prepare()
                let pack = try Self.loadVoicePack(voice)
                let tSession = ListenTimingLog.now()
                let (session, model) = try await CPURouteMetrics.onQueue(qos) {
                    // NaN-safe model (patched once from the download; see KokoroONNXModelPatch).
                    let model = CPURouteModelStore.ensurePatchedModel()
                    return (try KokoroONNXSession(modelURL: model.url, threads: threads, allowSpinning: false), model)
                }
                self.lock.withLock {
                    self.frontend = fe
                    self.session = session
                    self.packs[voice] = pack
                }
                ListenTimingLog.log("kokoro_cpu_init_end", [
                    "ok": true, "ms": ListenTimingLog.ms(since: t0), "download_ms": tDownloaded,
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

    func resetPrepared() {
        lock.withLock { didPrepare = false; prepareTask = nil }
    }

    func unload() async {
        lock.withLock {
            didPrepare = false
            prepareTask = nil
            session = nil
            frontend = nil
            packs.removeAll()
        }
    }

    func synthesizeOnce(text: String, seed: UInt64) async throws -> SynthesizedPCM {
        let (fe, session) = lock.withLock { (frontend, self.session) }
        guard let fe, let session else { throw LocalSynthError.engineUnavailable("Kokoro (CPU) not loaded") }
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
        let tRun = ListenTimingLog.now()
        var raw = try await CPURouteMetrics.onQueue(qos) { try session.run(inputs) }
        var nanRetry = false
        if !KokoroCPUAudio.allFinite(raw) {
            // Should not happen with the patched model; never write NaN (it becomes a full-scale
            // pop + silence). Retry once at a 2 % different speed (different frame count / rounding),
            // then give up so the queue speaks this chunk with Apple instead of dead air.
            ListenTimingLog.log("onnx_nonfinite", ["chars": text.count, "tokens": ids.count, "retry": true])
            var retryInputs = inputs
            retryInputs.speed = [1.02]
            raw = try await CPURouteMetrics.onQueue(qos) { try session.run(retryInputs) }
            nanRetry = true
            guard KokoroCPUAudio.allFinite(raw) else {
                ListenTimingLog.log("onnx_nonfinite", ["chars": text.count, "tokens": ids.count, "retry": false])
                throw LocalSynthError.engineUnavailable("Kokoro ONNX produced invalid audio (NaN)")
            }
        }
        let onnxMs = ListenTimingLog.ms(since: tRun)
        let gain = Self.gain
        let samples = raw.map { $0 * gain }
        Self.noteHealthyCall()
        return SynthesizedPCM(
            samples: samples,
            sampleRate: KokoroCPUAudio.sampleRate,
            metrics: [
                "phonemes": phonemes.count, "tokens": ids.count, "style_row": inputs.styleRow,
                "g2p_ms": g2pMs, "onnx_ms": onnxMs, "threads": threads, "nan_retry": nanRetry,
                "mem_mb": Self.footprintMB(),
            ]
        )
    }

    /// App memory footprint (what jetsam counts), MB; logged per call to watch chunk-size memory.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    private func voicePack(_ voice: String) throws -> [Float] {
        if let cached = lock.withLock({ packs[voice] }) { return cached }
        let pack = try Self.loadVoicePack(voice)
        lock.withLock { packs[voice] = pack }
        return pack
    }

    /// After a healthy stretch, forget earlier ONNX-route crashes (the "two crashes → Apple" rule
    /// counts crashes close together, not over the app's lifetime).
    private static func noteHealthyCall() {
        let reached: Bool = healthLock.withLock {
            healthyCalls += 1
            return healthyCalls == KokoroCrashRecovery.healthyRendersToReset
        }
        if reached {
            let settings = KokoroRouteSettings()
            if settings.onnxCrashCount > 0 {
                settings.onnxCrashCount = 0
                ListenTimingLog.log("kokoro_onnx_crash_count_reset", ["after_calls": KokoroCrashRecovery.healthyRendersToReset])
            }
        }
    }

    // MARK: - Files

    static func ensureVoicePackFile(_ voice: String) async throws {
        guard let dir = KokoroHost.repoDirectory else { throw LocalSynthError.engineUnavailable("No Application Support") }
        guard !KokoroHost.voicePackInstalled(voice) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t0 = ListenTimingLog.now()
        try await KokoroAneResourceDownloader.ensureVoicePack(voice, repoDirectory: dir, variant: .english)
        ListenTimingLog.log("kokoro_voice_download", ["voice": voice, "ms": ListenTimingLog.ms(since: t0)])
    }

    static func loadVoicePack(_ voice: String) throws -> [Float] {
        guard let dir = KokoroHost.repoDirectory else { throw LocalSynthError.engineUnavailable("No Application Support") }
        return try KokoroAneVoicePack.load(from: dir.appendingPathComponent("\(voice).bin")).storage
    }

    /// Everything the CPU route needs is on disk (cheap checks, no hashing).
    static var filesLookInstalled: Bool {
        CPURouteModelStore.fileLooksInstalled && KokoroAneCPUFrontend.assetsPresent()
    }

    // MARK: - KokoroCPURouteFrontend (debug benchmark; no Core ML)

    func cpuRoutePhonemes(for text: String) async throws -> String {
        let fe = try await loadedFrontend()
        return try await fe.phonemes(for: text)
    }

    func cpuRouteTokenIDs(for phonemes: String) async throws -> [Int32] {
        let fe = try await loadedFrontend()
        return try await fe.tokenIDs(for: phonemes)
    }

    func cpuRouteVoicePack(_ voice: String) async throws -> [Float] {
        try await Self.ensureVoicePackFile(voice)
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

/// Frontend-files presence check without importing FluidAudio at the call site.
enum KokoroAneCPUFrontendFiles {
    static var present: Bool { KokoroAneCPUFrontend.assetsPresent() }
}

// MARK: - Test / diagnostics hooks (simulator tests only; never called on device paths)

extension KokoroCPUHost {
    /// (repo dir holding `vocab.json`, kokoro dir holding the G2P bundle + lexicon).
    static func debugFrontendDirectories() throws -> (repo: URL, kokoro: URL) {
        (try KokoroAneCPUFrontend.defaultRepoDirectory(), try KokoroAneCPUFrontend.defaultKokoroDirectory())
    }

    /// Swift BART vs Core ML `G2PModel` on `words`; returns mismatches. Runs Core ML.
    static func debugCompareG2PWithCoreML(words: [String]) async throws -> [(word: String, swift: String, coreML: String)] {
        try await KokoroAneCPUFrontend.debugCompareWithCoreML(words: words)
    }

    /// Full ONNX-route frontend: text → IPA (lexicon + Swift BART), no Core ML.
    static func debugPhonemes(text: String) async throws -> (phonemes: String, oovWords: Int) {
        let frontend = try KokoroAneCPUFrontend()
        let p = try await frontend.phonemes(for: text)
        return (p, await frontend.oovWordCount)
    }
}

/// Test handle over the ONNX-route frontend (text → token ids + phoneme count), no Core ML.
final class KokoroAneCPUFrontendHandle: @unchecked Sendable {
    private let frontend: KokoroAneCPUFrontend
    init() throws { frontend = try KokoroAneCPUFrontend() }
    func ids(for text: String) async throws -> (ids: [Int32], phonemeCount: Int) {
        let p = try await frontend.phonemes(for: text)
        return (try await frontend.tokenIDs(for: p), p.count)
    }
}
