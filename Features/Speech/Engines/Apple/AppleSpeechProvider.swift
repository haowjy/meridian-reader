import Foundation

/// Apple `AVSpeechSynthesizer`: always available, no prepare, no bake cache. Playback is
/// driven directly by `SpeechController` (utterances), so there is no synth host.
@MainActor
final class AppleSpeechProvider: SpeechEngineProvider {
    let name = "Apple"

    /// Apple voices are picked in Settings' separate "Apple voice" section, not from here.
    static let descriptor = EngineDescriptor(
        id: .apple,
        displayName: "Apple",
        shortName: "Apple",
        subtitle: "System voices, always available",
        sortOrder: 0,
        onDevice: nil
    )

    var descriptors: [EngineDescriptor] { [Self.descriptor] }
    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? { nil }
    func isInstalled(_ id: SpeechEngineID) -> Bool { true }
    func deleteModels(_ id: SpeechEngineID) throws {}
}
