import Foundation
import SwiftUI

extension SpeechEngineID {
    /// Phonon 31m English (Apache 2.0). Core ML via Gradium `ptts`. Not the default.
    static let phonon = SpeechEngineID("local.phonon")
}

extension TextChunker.Limits {
    /// Phonon splits long text into sentences itself; keep first chunks short for TTFA.
    static let phonon = TextChunker.Limits(
        target: 360, hardMax: 480, firstTarget: 90, minResplit: 24,
        alwaysSplitFirst: true, secondTarget: 180)
}

/// Gradium Phonon 31m English adapter. Registers one on-device engine (`local.phonon`).
/// This PR runs Core ML on **CPU** only (`computeUnit: .cpu`) for the speed probe vs Kokoro.
@MainActor
final class PhononProvider: SpeechEngineProvider {
    let name = "Phonon"

    static let descriptor = EngineDescriptor(
        id: .phonon,
        displayName: "Phonon (on-device)",
        shortName: "Phonon",
        subtitle: "~131 MB download, English, CPU for now",
        isRecommended: false,
        sortOrder: 20,
        voices: PhononVoiceCatalog.curated,
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
        return PhononHost(voice: voice ?? PhononVoiceCatalog.defaultVoice, computeUnit: .cpu)
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
            && PhononVoiceCatalog.curated.contains(where: { $0.id == voice })
    }

    func debugSections(speech: SpeechController) -> AnyView {
        AnyView(EmptyView())
    }
}
