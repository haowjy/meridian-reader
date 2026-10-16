#if DEBUG
import Foundation

/// An on-device "voice" for UI tests (`-testVoice`, Debug builds only): it renders a soft tone
/// the length speech would be, a little slowly, through the whole render path (the queue, the
/// cache, bake marks, downloads), with nothing to download and no model. Two voices, so a voice
/// change can be tested. The Simulator has no Kokoro model, and UI tests stay offline.
@MainActor
final class TestVoiceProvider: SpeechEngineProvider {
    static let id = SpeechEngineID("test.voice")
    let name = "TestVoice"

    static let descriptor = EngineDescriptor(
        id: id,
        displayName: "Test Voice (UI tests)", shortName: "Test Voice", subtitle: "A tone, for UI tests",
        sortOrder: 90,
        voices: [EngineVoice(id: "one", label: "One"), EngineVoice(id: "two", label: "Two")],
        defaultVoiceID: "one",
        onDevice: OnDeviceTraits(cacheVoicePrefix: "testvoice",
                                 limits: .init(target: 120, hardMax: 160, firstTarget: 60, minResplit: 20)))

    var descriptors: [EngineDescriptor] { [Self.descriptor] }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        id == Self.id ? TestVoiceHost(engineID: id) : nil
    }

    func isInstalled(_ id: SpeechEngineID) -> Bool { true }
    func deleteModels(_ id: SpeechEngineID) throws {}
}

private final class TestVoiceHost: LocalSynthHost, @unchecked Sendable {
    let engineID: SpeechEngineID
    /// Seconds each render takes: slow enough that a download's progress shows.
    private let delay: TimeInterval = 0.15
    var routingLabel: String? { "test" }
    var onProgress: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var prepared = false

    init(engineID: SpeechEngineID) {
        self.engineID = engineID
    }

    var isPrepared: Bool { lock.withLock { prepared } }

    func prepare() async throws {
        onProgress?(1)
        lock.withLock { prepared = true }
    }

    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        let rate = 24_000
        let count = max(1, Int(Double(text.count) * 0.06 * Double(rate)))
        let samples = (0..<count).map { Float(sin(2 * Double.pi * 220 * Double($0) / Double(rate)) * 0.02) }
        return SynthesizedPCM(samples: samples, sampleRate: rate)
    }

    func setVoice(_ voice: String) {}
    func unload() async { lock.withLock { prepared = false } }
}
#endif
