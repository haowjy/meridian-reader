// speech-swift adapter (soniqo/speech-swift, Apache-2.0) — PLACEHOLDER.
//
// Compiled only once the package is added (SPM product `Qwen3TTSCoreML`, iOS 18+), so this file
// is inert today. To enable: add the package + product to project.yml (see
// docs/TTS_ENGINES_SKETCH.md § "How to add an engine/library"). The registration line in
// `App/AppComposition.swift` is already there behind the same `#if canImport`. API below matches speech-swift main as of 2026-09-24
// (`Qwen3TTSCoreMLModel.fromPretrained(progressHandler:)`, `synthesize(text:language:maxTokens:)`
// → 24 kHz `[Float]`, ≤125 codec tokens ≈ 10 s per call); verify against the pinned version.
#if canImport(Qwen3TTSCoreML)
import Foundation
import Qwen3TTSCoreML

extension SpeechEngineID {
    static let qwen3TTS = SpeechEngineID("local.qwen3-tts")
}

@MainActor
final class SpeechSwiftProvider: SpeechEngineProvider {
    let name = "speech-swift"

    static let qwen3Descriptor = EngineDescriptor(
        id: .qwen3TTS,
        providerName: "speech-swift",
        kind: .onDevice,
        displayName: "Qwen3-TTS (on-device)",
        shortName: "Qwen3",
        subtitle: "Experimental · large download",
        isRecommended: false,
        sortOrder: 30,
        voices: [],
        defaultVoiceID: nil,
        voiceDefaultsKey: nil,
        cacheVoiceKey: .prefixed("qwen3"),
        streaming: .wholeCall,
        // ≤125 codec tokens ≈ 10 s audio per call → `.tenSecondCall` until measured.
        limits: .tenSecondCall,
        limitNotes: "maxTokens 125 (≈10 s) per call; measure s/char on device before widening.",
        assets: [.init(name: "Qwen3-TTS CoreML 0.6B", approxBytes: 0, source: "hf:aufklarer/Qwen3-TTS-CoreML")],
        approxDownloadBytes: 0,
        hardware: HardwareRequirement(minimumOSMajor: 18, minimumChip: .a17OrNewer, allowsSimulator: false,
                                      summary: "iPhone 15 Pro or newer · iOS 18+"),
        computeRouting: "cpuAndNeuralEngine (bundle default)",
        quirks: [],
        supportsBakeCache: true,
        crashGuarded: true,
        crashNoticeDetail: "Core ML crash"
    )

    var descriptors: [EngineDescriptor] { [Self.qwen3Descriptor] }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == .qwen3TTS, #available(iOS 18.0, *) else { return nil }
        return Qwen3Host()
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool { false /* TODO: check HF cache dir */ }
    func deleteModels(_ id: SpeechEngineID) throws { /* TODO: remove HF cache dir */ }
}

@available(iOS 18.0, *)
final class Qwen3Host: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID = .qwen3TTS
    var routingLabel: String? { nil }
    var onProgress: (@Sendable (Double) -> Void)?
    private var model: Qwen3TTSCoreMLModel?
    private let lock = NSLock()

    var isPrepared: Bool { lock.withLock { model != nil } }

    func prepare() async throws {
        if isPrepared { return }
        let progress = onProgress
        await SynthRenderGate.shared.acquire()
        do {
            let m = try await Qwen3TTSCoreMLModel.fromPretrained(progressHandler: { p, _ in progress?(p) })
            lock.withLock { model = m }
            await SynthRenderGate.shared.release()
        } catch {
            await SynthRenderGate.shared.release()
            throw error
        }
    }

    func synthesizeOnce(text: String, seed: UInt64) async throws -> SynthesizedPCM {
        guard let model = lock.withLock({ model }) else { throw LocalSynthError.engineUnavailable("Qwen3 not loaded") }
        // Map the library's "too many tokens" error to .inputTooLong so LocalChunkRenderer re-splits.
        let samples = try model.synthesize(text: text, language: "english")
        return SynthesizedPCM(samples: samples, sampleRate: 24_000)
    }

    func setVoice(_ voice: String) {}
    func resetPrepared() { lock.withLock { model = nil } }
    func unload() async { resetPrepared() }
}
#endif
