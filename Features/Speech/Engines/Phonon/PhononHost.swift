import Foundation
import PhononTTS

/// Phonon 31m English via Gradium `ptts` / Core ML.
/// This PR forces `computeUnit: .cpu` so Jimmy can compare CPU speed to Kokoro ONNX CPU.
/// Desktop GGUF "q8" is a different stack; label probe rows `phonon-31m cpu`.
final class PhononHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .phonon
    /// Always CPU for this PR (ANE is Phonon's default; we override for the probe).
    let computeUnit: ComputeUnit
    var routingLabel: String? { "phonon-31m cpu" }
    var routeTag: String? { "cpu" }
    /// Core ML path; prove background later. Default LocalSynthHost is false.
    var rendersInBackground: Bool { false }
    var onProgress: (@Sendable (Double) -> Void)?

    private let load = SingleFlightLoad()
    private let lock = NSLock()
    private var voice: String
    private var tts: Phonon?

    init(voice: String = PhononVoiceCatalog.defaultVoice,
         computeUnit: ComputeUnit = .cpu) {
        self.voice = voice
        self.computeUnit = computeUnit
    }

    var isPrepared: Bool { load.isLoaded }

    func setVoice(_ voice: String) { lock.withLock { self.voice = voice } }
    private var currentVoice: String { lock.withLock { voice } }

    func prepare() async throws {
        let progress = onProgress
        let voice = currentVoice
        let unit = computeUnit
        try await load.run {
            let t0 = ListenTimingLog.now()
            let onDisk = PhononModelStore.filesLookInstalled
            ListenTimingLog.log("phonon_init_start", [
                "voice": voice, "unit": "cpu", "models_on_disk": onDisk,
            ])
            do {
                progress?(0.02)
                try await PhononModelStore.shared.ensureInstalled { f in
                    progress?(0.02 + 0.75 * f)
                }
                try Task.checkCancellation()
                progress?(0.80)
                await SynthRenderGate.shared.acquire()
                let loaded: Phonon
                do {
                    let needs = Phonon.needsCompiling(PhononModelStore.modelsDirectory)
                    ListenTimingLog.log("phonon_load_start", ["needs_compiling": needs])
                    loaded = try await Phonon.load(
                        models: PhononModelStore.modelsDirectory,
                        language: .english,
                        computeUnit: unit)
                    if voice != loaded.voice {
                        try await loaded.setVoice(voice)
                    }
                    await SynthRenderGate.shared.release()
                } catch {
                    await SynthRenderGate.shared.release()
                    throw error
                }
                self.lock.withLock { self.tts = loaded }
                progress?(1)
                ListenTimingLog.log("phonon_init_ready", [
                    "ms": ListenTimingLog.ms(since: t0),
                    "voice": loaded.voice,
                    "voices": loaded.voices.count,
                ])
            } catch {
                ListenTimingLog.log("phonon_init_failed", [
                    "ms": ListenTimingLog.ms(since: t0),
                    "err": error.localizedDescription,
                ])
                throw error
            }
        }
    }

    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalSynthError.emptyText }
        guard let tts = lock.withLock({ self.tts }) else {
            throw LocalSynthError.engineUnavailable("Phonon is not loaded")
        }
        let want = currentVoice
        if want != tts.voice {
            try await tts.setVoice(want)
        }
        let t0 = ListenTimingLog.now()
        let samples: [Float]
        do {
            samples = try await tts.synthesize(trimmed)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalSynthError.engineUnavailable(error.localizedDescription)
        }
        let audioS = Double(samples.count) / Phonon.sampleRate
        let wallMs = ListenTimingLog.ms(since: t0)
        return SynthesizedPCM(
            samples: samples,
            sampleRate: Int(Phonon.sampleRate),
            metrics: [
                "engine": "phonon",
                "unit": "cpu",
                "wall_ms": wallMs,
                "audio_s": audioS,
                "rtf": audioS > 0 ? (Double(wallMs) / 1000.0) / audioS : 0,
            ])
    }

    func unload() async {
        await load.close()
        lock.withLock { tts = nil }
        load.reset()
    }
}
