import Foundation
import PhononTTS

/// Phonon 31m English via Gradium `ptts` / Core ML.
/// Normal listening uses Phonon's default compute unit (Neural Engine). `computeUnit: .cpu` is an
/// optional debug route (the earlier CPU probe); CPU-only rendering made the phone laggy.
final class PhononHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .phonon
    /// nil = Phonon default (Neural Engine). `.cpu` only for the debug probe.
    let computeUnit: ComputeUnit?
    var routingLabel: String? { computeUnit == nil ? "phonon-31m ane" : "phonon-31m cpu" }
    var routeTag: String? { computeUnit == nil ? "ane" : "cpu" }
    private var unitTag: String { computeUnit == nil ? "ane" : "cpu" }
    /// Core ML path; prove background later. Default LocalSynthHost is false.
    var rendersInBackground: Bool { false }
    var onProgress: (@Sendable (Double) -> Void)?

    private let load = SingleFlightLoad()
    private let lock = NSLock()
    private var voice: String
    private var tts: Phonon?

    init(voice: String = PhononVoiceCatalog.defaultVoice,
         computeUnit: ComputeUnit? = nil) {
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
        let tag = unitTag
        try await load.run {
            let t0 = ListenTimingLog.now()
            let onDisk = PhononModelStore.filesLookInstalled
            ListenTimingLog.log("phonon_init_start", [
                "voice": voice, "unit": tag, "models_on_disk": onDisk,
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
                    if let unit {
                        loaded = try await Phonon.load(
                            models: PhononModelStore.modelsDirectory,
                            language: .english,
                            computeUnit: unit)
                    } else {
                        loaded = try await Phonon.load(
                            models: PhononModelStore.modelsDirectory,
                            language: .english)
                    }
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
                "unit": unitTag,
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
