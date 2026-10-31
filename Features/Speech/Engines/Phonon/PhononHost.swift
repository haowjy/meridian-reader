import Foundation
import PhononTTS

/// Phonon 31m English via Gradium `ptts`, on Core ML's CPU path (`computeUnit: .cpu`), in front
/// and in the background alike. Audio sounds the same as on the Neural Engine, so its cache key
/// doesn't name the compute unit.
final class PhononHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .phonon
    static let computeUnit: ComputeUnit = .cpu
    var routingLabel: String? { "phonon-31m cpu" }
    var onProgress: (@Sendable (Double) -> Void)?

    private let load = SingleFlightLoad()
    private let lock = NSLock()
    private var voice: String
    private var tts: Phonon?

    init(voice: String = PhononVoiceCatalog.defaultVoice) {
        self.voice = voice
    }

    var isPrepared: Bool { load.isLoaded }

    /// Thin Phonon-only footgun fixes (`?…`, shouty ALL CAPS). Gradium's own normalizer
    /// (`normalize_text` / `Normalize::for_lang(.en)`) still runs automatically inside
    /// `tts.synthesize` — we do not reimplement numbers/symbols here. See `synthesizeOnce`.
    func spokenText(forChunk text: String) -> String { PhononSpokenText.prepare(text) }

    func setVoice(_ voice: String) { lock.withLock { self.voice = voice } }
    private var currentVoice: String { lock.withLock { voice } }

    func prepare() async throws {
        let progress = onProgress
        let voice = currentVoice
        try await load.run {
            let t0 = ListenTimingLog.now()
            ListenTimingLog.log("phonon_init_start", ["voice": voice, "unit": "cpu"])
            do {
                progress?(0.02)
                try await PhononModelStore.ensureInstalled()
                try Task.checkCancellation()
                progress?(0.80)
                await SynthRenderGate.of(.cpu).acquire()
                let loaded: Phonon
                do {
                    let needs = Phonon.needsCompiling(PhononModelStore.modelsDirectory)
                    ListenTimingLog.log("phonon_load_start", ["needs_compiling": needs])
                    // `language: .english` turns Gradium normalize ON (Normalize::for_lang(En)).
                    // `.none` would skip it. Numbers / @ / + / = / currency / … are rewritten
                    // inside every later `synthesize` — no separate Swift `normalize()` call.
                    loaded = try await Phonon.load(
                        models: PhononModelStore.modelsDirectory,
                        language: .english,
                        computeUnit: Self.computeUnit)
                    if voice != loaded.voice {
                        try await loaded.setVoice(voice)
                    }
                    await SynthRenderGate.of(.cpu).release()
                } catch {
                    await SynthRenderGate.of(.cpu).release()
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

    /// Core ML takes no thread count: `threads` is nil for its route.
    func synthesizeOnce(text: String, priority: RenderPriority, threads: Int?) async throws -> SynthesizedPCM {
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
        // Pipeline into Phonon: Meridian `TTSTextNormalize` (whitespace only) → chunk →
        // `PhononSpokenText.prepare` (footguns) → here. Gradium then runs its English
        // `normalize_text` automatically (language set at load): spells numbers/symbols,
        // turns em/en dashes into spaces, spaced `;`/`:` into comma pauses, `…`→`.`.
        // Meridian no longer rewrites dashes/semicolons into pauses — Gradium owns that.
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
