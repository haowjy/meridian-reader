import Foundation

/// Apple `AVSpeechSynthesizer`: always available, no download, no bake cache. Playback is
/// driven directly by `SpeechController` (utterances), so there is no synth host.
@MainActor
final class AppleSpeechProvider: SpeechEngineProvider {
    let name = "Apple"

    static let descriptor = EngineDescriptor(
        id: .apple,
        providerName: "Apple",
        kind: .system,
        displayName: "Apple",
        shortName: "Apple",
        subtitle: "System voices · always available",
        isRecommended: false,
        sortOrder: 0,
        voices: [], // Apple voices are picked in the separate "Apple voice" section
        defaultVoiceID: nil,
        voiceDefaultsKey: "reader.selectedVoiceIdentifier",
        cacheVoiceKey: .appleVoice,
        streaming: EngineStreaming(streams: true, yieldsPCMChunks: false),
        limits: .tenSecondCall, // only used to split Apple *fallback* text; any sane size works
        limitNotes: "No per-call cap that matters; utterances are whole paragraphs.",
        assets: [],
        approxDownloadBytes: 0,
        hardware: .none,
        computeRouting: nil,
        quirks: [],
        supportsBakeCache: false,
        crashGuarded: false,
        crashNoticeDetail: nil
    )

    var descriptors: [EngineDescriptor] { [Self.descriptor] }
    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? { nil }
    func isInstalled(_ id: SpeechEngineID) -> Bool { true }
    func deleteModels(_ id: SpeechEngineID) throws {}
}
