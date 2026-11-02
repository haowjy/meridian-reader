import Foundation
import SwiftUI

extension SpeechEngineID {
    /// Phonon 31m English (Apache 2.0). Core ML via Gradium `ptts`. App default on-device engine.
    static let phonon = SpeechEngineID("local.phonon")
}

extension TextChunker.Limits {
    /// Phonon prefers whole-paragraph synth calls. Display paragraphs are capped around
    /// 1,200 chars (`ParagraphSplitter.threshold`); Phonon's own sentence handling and speed
    /// make short TTFA first-clips unnecessary for normal listening. Oversized rare
    /// paragraphs still sentence-split via TextChunker under `hardMax`.
    static let phonon = TextChunker.Limits(
        target: 1200, hardMax: 1600, firstTarget: 1200, minResplit: 48,
        alwaysSplitFirst: false, secondTarget: nil)
}

/// Gradium Phonon 31m English adapter. Registers one on-device engine (`local.phonon`), on two
/// routes: Core ML's CPU path and the Neural Engine.
@MainActor
final class PhononProvider: SpeechEngineProvider {
    let name = "Phonon"

    static let descriptor = EngineDescriptor(
        id: .phonon,
        displayName: "Phonon",
        shortName: "Phonon",
        isRecommended: true,
        sortOrder: 10,
        voices: PhononVoiceCatalog.curated,
        moreVoices: PhononVoiceCatalog.more,
        defaultVoiceID: PhononVoiceCatalog.defaultVoice,
        voiceDefaultsKey: "reader.tts.phononVoice",
        hardware: HardwareRequirement(
            minimumOSMajor: 18,
            minimumChip: nil,
            allowsSimulator: true,
            summary: "iOS 18 or later"),
        supportedLanguages: ["en"],
        onDevice: OnDeviceTraits(
            cacheVoicePrefix: "phonon",
            cacheRevision: String(PhononModelStore.bundleBuilt),
            limits: .phonon,
            isCrashGuarded: true)
    )

    var descriptors: [EngineDescriptor] { [Self.descriptor] }

    var regenerableDirectories: [URL] { [PhononModelStore.rootDirectory] }

    /// Core ML's CPU path and the Neural Engine, neither of which takes a thread count; one cache
    /// revision for both (the owner heard no difference). Footprints from the phone: about 120 MiB
    /// for a CPU host, about 300 MiB more for a Neural Engine host beside it (430 MiB both, p433).
    /// The app's policy uses the CPU route alone; `LanePolicy` both.
    var routes: [RenderRoute] {
        [RenderRoute(id: "phonon.cpu", engine: .phonon, lane: .cpu, threads: .uncapped, footprintMB: 120),
         RenderRoute(id: "phonon.ane", engine: .phonon, lane: .neuralEngine, threads: .uncapped, footprintMB: 300)]
    }

    func makeHost(for route: RenderRoute, voice: String?) -> LocalSynthHost? {
        guard route.engine == .phonon else { return nil }
        return PhononHost(voice: voice ?? PhononVoiceCatalog.defaultVoice, lane: route.lane)
    }

    /// The model bundle ships in the app (`PhononModelStore`): always installed.
    func isInstalled(_ id: SpeechEngineID) -> Bool { id == .phonon }

    /// A voice's file in the shipped bundle (`voices/<id>.safetensors`), measured once.
    func installedSize(of voice: String, for id: SpeechEngineID) -> Int64? {
        guard id == .phonon else { return nil }
        if let known = voiceSizes[voice] { return known }
        guard let bundle = PhononModelStore.shippedBundle else { return nil }
        let bytes = FileSizes.allocatedBytes(at: bundle.appendingPathComponent("voices/\(voice).safetensors"))
        guard bytes > 0 else { return nil }
        voiceSizes[voice] = bytes
        return bytes
    }

    /// The bundle's voice files never change while the app runs.
    private var voiceSizes: [String: Int64] = [:]

    /// Phonon's model housekeeping, then pruning Core ML's compiled-model cache of earlier
    /// installs' bundles (Phonon is the app's only Core ML model).
    var launchMigrations: [LaunchMigration] {
        [PhononDownloadLeftovers(), PhononCacheRevision(), CoreMLCompileCacheJanitor()]
    }

    func debugSections(speech: SpeechController) -> AnyView {
        AnyView(EmptyView())
    }
}
