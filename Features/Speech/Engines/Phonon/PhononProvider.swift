import Foundation
import SwiftUI

extension SpeechEngineID {
    /// Phonon 31m English (Apache 2.0). Core ML via Gradium `ptts`. App default on-device engine.
    static let phonon = SpeechEngineID("local.phonon")
}

extension TextChunker.Limits {
    /// Phonon prefers whole-paragraph synth calls. Display paragraphs are capped around
    /// 1,200 chars (`ParagraphSplitter.threshold`); Phonon's own sentence handling + ANE
    /// make short TTFA first-clips unnecessary for normal listening. Oversized rare
    /// paragraphs still sentence-split via TextChunker under `hardMax`.
    static let phonon = TextChunker.Limits(
        target: 1200, hardMax: 1600, firstTarget: 1200, minResplit: 48,
        alwaysSplitFirst: false, secondTarget: nil)
}

/// Gradium Phonon 31m English adapter. Registers one on-device engine (`local.phonon`).
/// Core ML on Phonon's default compute unit (Neural Engine).
@MainActor
final class PhononProvider: SpeechEngineProvider {
    let name = "Phonon"

    static let descriptor = EngineDescriptor(
        id: .phonon,
        displayName: "Phonon (on-device)",
        shortName: "Phonon",
        subtitle: "Recommended, ~131 MB download",
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
            summary: "iOS 18+ (Phonon Core ML)"),
        supportedLanguages: ["en"],
        onDevice: OnDeviceTraits(
            cacheVoicePrefix: "phonon",
            limits: .phonon,
            crashNotice: "Phonon stopped unexpectedly")
    )

    var descriptors: [EngineDescriptor] { [Self.descriptor] }

    var regenerableDirectories: [URL] { [PhononModelStore.rootDirectory] }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == .phonon else { return nil }
        return PhononHost(voice: voice ?? PhononVoiceCatalog.defaultVoice)
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool {
        id == .phonon && PhononModelStore.filesLookInstalled
    }

    func deleteModels(_ id: SpeechEngineID) throws {
        guard id == .phonon else { return }
        PhononModelStore.shared.delete()
    }

    /// Voices live inside the model bundle; once the bundle is installed every curated voice is present.
    func isVoicePackInstalled(_ voice: String, for id: SpeechEngineID) -> Bool {
        id == .phonon && PhononModelStore.filesLookInstalled
            && PhononVoiceCatalog.all.contains(where: { $0.id == voice })
    }

    func debugSections(speech: SpeechController) -> AnyView {
        AnyView(EmptyView())
    }
}
