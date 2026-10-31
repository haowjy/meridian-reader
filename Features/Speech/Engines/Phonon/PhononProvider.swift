import Foundation
import SwiftUI

extension SpeechEngineID {
    /// Phonon 31m English (Apache 2.0). Core ML's CPU path via Gradium `ptts`. App default on-device engine.
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

/// Gradium Phonon 31m English adapter. Registers one on-device engine (`local.phonon`).
/// Core ML's CPU path (`PhononHost.computeUnit`).
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

    /// Core ML's CPU path, which takes no thread count.
    var routes: [RenderRoute] { [RenderRoute(id: "phonon.cpu", engine: .phonon, lane: .cpu, threads: .uncapped)] }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == .phonon else { return nil }
        return PhononHost(voice: voice ?? PhononVoiceCatalog.defaultVoice)
    }

    /// The model bundle ships in the app (`PhononModelStore`): always installed.
    func isInstalled(_ id: SpeechEngineID) -> Bool { id == .phonon }

    /// Every catalog voice is in the shipped bundle.
    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool {
        id == .phonon && PhononVoiceCatalog.all.contains(where: { $0.id == voice })
    }

    /// Phonon's model housekeeping, then pruning Core ML's compiled-model cache of earlier
    /// installs' bundles (Phonon is the app's only Core ML model).
    var launchMigrations: [LaunchMigration] {
        [PhononDownloadLeftovers(), PhononCacheRevision(), CoreMLCompileCacheJanitor()]
    }

    func debugSections(speech: SpeechController) -> AnyView {
        AnyView(EmptyView())
    }
}
