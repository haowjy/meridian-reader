import FluidAudio
import Foundation

/// Kokoro 82M via FluidAudio `KokoroAneManager` (vendored v0.16.1, `TTS/KokoroAne`): the Core ML
/// half of the **Core ML route** (`KokoroSplitHost`, which hands background calls to ONNX). Only
/// used when the debug toggle "Kokoro fast GPU route (may crash on iOS 26.4+)" is on; the default
/// is `KokoroCPUHost` (ONNX CPU).
/// Thin host: download + load, one `synthesizeDetailed` call, map overflow errors.
/// Chunking / re-split / gate / crash guard / CAF live in `LocalChunkRenderer`.
///
/// - Models: HF `FluidInference/kokoro-82m-coreml/ANE` — 7 compiled stages (≈82 MB), `vocab.json`,
///   voice packs (0.5 MB each). English G2P: BART `G2PEncoder/Decoder.mlmodelc` (≈1.6 MB) +
///   Misaki `us_lexicon_cache.json` (≈10 MB). No espeak.
///   Cached under `Application Support/fluidaudio/Models/{kokoro-82m-coreml/ANE, kokoro}`.
/// - Per call: ≤510 IPA phonemes (`phonemeSequenceTooLong`), ≤2000 frames (`acousticFramesExceedCap`).
/// - Deterministic: the same text renders the same audio.
final class KokoroHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .kokoro

    private let manager: KokoroAneManager
    private let load = SingleFlightLoad()
    private let lock = NSLock()
    private var voice: String
    var onProgress: (@Sendable (Double) -> Void)?

    static let defaultVoice = KokoroAneConstants.defaultVoice // "af_heart"

    /// Compute routing: `aneTailGpu` (FluidAudio #667) on every OS: the RNN stages on
    /// `.cpuAndNeuralEngine`, noise and the iSTFT tail on `.cpuAndGPU`, so the tail never runs on
    /// the CPU (BNNS). Pinned rather than FluidAudio's `.default`, which moves noise and tail to
    /// `.cpuOnly` on OS 27.
    /// Debug knob (`FluidAudioProvider.coreMLUnits`, from `-kokoroUnits`):
    /// `default|cpuAndGpu|cpuOnly|allAne|aneTailGpu|aneTailCpu|gpuAneVocoder|aneFrontGpuBack`.
    let unitsLabel: String
    var routingLabel: String? { unitsLabel }
    var routeTag: String? { KokoroRoute.coreMLGPU.rawValue }

    static let defaultUnitsLabel = "aneTailGpu"

    init(voice: String = KokoroHost.defaultVoice, units: String? = nil) {
        self.voice = voice
        let label = units ?? Self.defaultUnitsLabel
        self.unitsLabel = label
        let units: KokoroAneComputeUnits
        switch label {
        case "cpuAndGpu": units = .cpuAndGpu
        case "cpuOnly": units = .cpuOnly
        case "allAne": units = .allAne
        case "aneTailGpu": units = .aneTailGpu
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

    var currentVoice: String {
        lock.withLock { voice }
    }

    var isPrepared: Bool { load.isLoaded }

    func prepare() async throws {
        let progress = onProgress
        let voice = currentVoice
        let manager = self.manager
        let units = unitsLabel
        try await load.run {
            let t0 = ListenTimingLog.now()
            ListenTimingLog.log("kokoro_init_start", ["voice": voice, "units": units])
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
                    try await manager.initialize(preloadVoices: [voice])
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

    func unload() async {
        await load.close()
        await manager.cleanup()
    }

    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM {
        // FluidAudio reloads released models on the next call: an unloaded host never calls it.
        guard load.isLoaded else { throw LocalSynthError.engineUnavailable("Kokoro (Core ML) not loaded") }
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
}
