import FluidAudio
import Foundation

/// Kokoro 82M via FluidAudio `KokoroAneManager` (vendored v0.16.1, `TTS/KokoroAne`) — the
/// **Core ML route**. Since 2026-09-24 only used when the debug toggle "Kokoro fast GPU route
/// (may crash on iOS 26.4+)" is on; the default is `KokoroCPUHost` (ONNX CPU). Never renders in
/// the background (`rendersInBackground` = false).
/// Thin host: download + load, one `synthesizeDetailed` call, map overflow errors.
/// Chunking / re-split / gate / crash guard / CAF live in `LocalChunkRenderer`.
///
/// - Models: HF `FluidInference/kokoro-82m-coreml/ANE` — 7 compiled stages (≈82 MB), `vocab.json`,
///   voice packs (0.5 MB each). English G2P: BART `G2PEncoder/Decoder.mlmodelc` (≈1.6 MB) +
///   Misaki `us_lexicon_cache.json` (≈10 MB). No espeak.
///   Cached under `Application Support/fluidaudio/Models/{kokoro-82m-coreml/ANE, kokoro}`.
/// - Per call: ≤510 IPA phonemes (`phonemeSequenceTooLong`), ≤2000 frames (`acousticFramesExceedCap`).
/// - Deterministic; the seed is ignored.
final class KokoroHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .kokoro

    private let manager: KokoroAneManager
    private let lock = NSLock()
    private var didPrepare = false
    private var prepareTask: Task<Void, Error>?
    private var voice: String
    var onProgress: (@Sendable (Double) -> Void)?

    static let defaultVoice = KokoroAneConstants.defaultVoice // "af_heart"

    /// Compute routing. On iOS 26.4–26.x all stages run on `.cpuAndGPU` except the vocoder on
    /// `.cpuAndNeuralEngine` ("gpuAneVocoder"): FluidAudio's default ANE routing crashed in libBNNS
    /// on Jimmy's iPhone 17 Pro / iOS 26.6.2; gpuAneVocoder ran ~180 calls crash-free at ~18×.
    /// Debug knob: `-kokoroUnits default|cpuAndGpu|cpuOnly|allAne|aneTailCpu|gpuAneVocoder|aneFrontGpuBack`.
    let unitsLabel: String
    var routingLabel: String? { unitsLabel }
    var routeTag: String? { KokoroRoute.coreMLGPU.rawValue }

    static var defaultUnitsLabel: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        if v.majorVersion == 26, v.minorVersion >= 4 { return "gpuAneVocoder" }
        #endif
        return "default"
    }

    static var launchArgUnits: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-kokoroUnits"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    init(voice: String = KokoroHost.defaultVoice, unitsOverride: String? = nil) {
        self.voice = voice
        let label = unitsOverride ?? Self.launchArgUnits ?? Self.defaultUnitsLabel
        self.unitsLabel = label
        let units: KokoroAneComputeUnits
        switch label {
        case "cpuAndGpu": units = .cpuAndGpu
        case "cpuOnly": units = .cpuOnly
        case "allAne": units = .allAne
        case "aneTailCpu": units = .aneTailCpu
        case "gpuAneVocoder":
            units = KokoroAneComputeUnits(
                albert: .cpuAndGPU, postAlbert: .cpuAndGPU, alignment: .cpuAndGPU, prosody: .cpuAndGPU,
                noise: .cpuAndGPU, vocoder: .cpuAndNeuralEngine, tail: .cpuAndGPU)
        case "aneFrontGpuBack":
            units = KokoroAneComputeUnits(
                albert: .cpuAndNeuralEngine, postAlbert: .cpuAndNeuralEngine, alignment: .cpuAndNeuralEngine,
                prosody: .cpuAndGPU, noise: .cpuAndGPU, vocoder: .cpuAndGPU, tail: .cpuAndGPU)
        default: units = .default
        }
        self.manager = KokoroAneManager(variant: .english, defaultVoice: voice, computeUnits: units)
        // Name the Core ML model + stage before every prediction (G2P BART and the 7 Kokoro
        // stages), so a libBNNS crash on the next launch says which one died.
        CoreMLBreadcrumb.setHandler { model, stage, detail in
            CoreMLBreadcrumbFile.shared.write(model: model, stage: stage, detail: detail)
        }
    }

    func setVoice(_ voice: String) {
        lock.withLock { self.voice = voice }
    }

    private var currentVoice: String {
        lock.withLock { voice }
    }

    var isPrepared: Bool {
        lock.withLock { didPrepare }
    }

    func prepare() async throws {
        // Single-flight: the first caller creates the load task, later callers await it.
        let task: Task<Void, Error>? = lock.withLock {
            if didPrepare { return nil }
            if let existing = prepareTask { return existing }
            let created = makePrepareTask()
            prepareTask = created
            return created
        }
        guard let task else { return }
        do {
            try await task.value
            lock.withLock { didPrepare = true; prepareTask = nil }
        } catch {
            lock.withLock { didPrepare = false; prepareTask = nil }
            throw error
        }
    }

    /// Called with `lock` held (don't touch `currentVoice` here — NSLock isn't recursive).
    private func makePrepareTask() -> Task<Void, Error> {
        let progress = onProgress
        let voice = self.voice
        return Task {
            let t0 = ListenTimingLog.now()
            ListenTimingLog.log("kokoro_init_start", ["voice": voice, "units": self.unitsLabel])
            do {
                // Fetch the 7-stage chain first so Settings can show byte progress;
                // `initialize()` then finds everything cached and just loads.
                try await KokoroAneResourceDownloader.ensureModels(
                    variant: .english,
                    progressHandler: { p in progress?(p.fractionCompleted) }
                )
                let tDownloaded = ListenTimingLog.ms(since: t0)
                await SynthRenderGate.shared.acquire()
                do {
                    try await self.manager.initialize(preloadVoices: [voice])
                    await SynthRenderGate.shared.release()
                } catch {
                    await SynthRenderGate.shared.release()
                    throw error
                }
                ListenTimingLog.log("kokoro_init_end", [
                    "ok": true, "ms": ListenTimingLog.ms(since: t0), "download_ms": tDownloaded,
                ])
            } catch {
                ListenTimingLog.log("kokoro_init_end", [
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
        resetPrepared()
        await manager.cleanup()
    }

    func synthesizeOnce(text: String, seed: UInt64) async throws -> SynthesizedPCM {
        do {
            let r = try await manager.synthesizeDetailed(text: text, voice: currentVoice, speed: 1.0)
            let st = r.timings
            return SynthesizedPCM(
                samples: r.samples,
                sampleRate: KokoroAneConstants.sampleRate,
                metrics: [
                    "phonemes": r.phonemes.count,
                    "frames": r.acousticFrames,
                    "stages_ms": [st.albert, st.postAlbert, st.alignment, st.prosody, st.noise, st.vocoder, st.tail]
                        .map { Int($0.rounded()) },
                ]
            )
        } catch let error as KokoroAneError {
            switch error {
            case .phonemeSequenceTooLong, .acousticFramesExceedCap:
                throw LocalSynthError.inputTooLong(error.localizedDescription)
            default:
                throw error
            }
        }
    }

    /// `Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE` (FluidAudio's English repo dir).
    static var repoDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fluidaudio/Models/kokoro-82m-coreml/ANE", isDirectory: true)
    }

    static func voicePackInstalled(_ voice: String) -> Bool {
        guard let dir = repoDirectory else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(voice).bin").path)
    }

    /// Download + convert a voice pack if it isn't on disk yet (FluidAudio fetches
    /// `voices/<id>.json` from the HF repo root and writes `<id>.bin`). Before the models are
    /// downloaded there's nothing to do: `prepare()` preloads the selected voice.
    static func ensureVoicePack(_ voice: String) async throws {
        guard let dir = repoDirectory, FileManager.default.fileExists(atPath: dir.path) else { return }
        guard !voicePackInstalled(voice) else { return }
        let t0 = ListenTimingLog.now()
        try await KokoroAneResourceDownloader.ensureVoicePack(voice, repoDirectory: dir, variant: .english)
        ListenTimingLog.log("kokoro_voice_download", ["voice": voice, "ms": ListenTimingLog.ms(since: t0)])
    }

    /// Removes Kokoro models + shared English G2P/lexicon from FluidAudio's cache.
    static func clearCachedModels() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let models = base.appendingPathComponent("fluidaudio/Models", isDirectory: true)
        try? fm.removeItem(at: models.appendingPathComponent("kokoro-82m-coreml", isDirectory: true))
        try? fm.removeItem(at: models.appendingPathComponent("kokoro", isDirectory: true))
    }

    /// Delete the 7 Core ML stage bundles (keeps vocab, voice packs, G2P + lexicon). Returns bytes freed.
    @discardableResult
    static func deleteCoreMLStages(fileManager fm: FileManager = .default) -> Int64 {
        guard let dir = repoDirectory, let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var freed: Int64 = 0
        for name in items where name.hasSuffix(".mlmodelc") || name.hasSuffix(".mlpackage") {
            let url = dir.appendingPathComponent(name)
            let bytes = FileSizes.allocatedBytes(at: url, fileManager: fm)
            if (try? fm.removeItem(at: url)) != nil { freed += bytes }
        }
        return freed
    }

    /// True when the 7-stage chain appears to be on disk (cheap existence check).
    static var modelsLookInstalled: Bool {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let dir = base.appendingPathComponent("fluidaudio/Models/kokoro-82m-coreml/ANE", isDirectory: true)
        return fm.fileExists(atPath: dir.appendingPathComponent("KokoroVocoder.mlmodelc").path)
    }
}
