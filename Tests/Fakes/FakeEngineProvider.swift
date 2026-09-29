import Foundation
@testable import Reader

/// Deterministic test engine: a 440 Hz tone (or silence) of 50 ms per character, with
/// configurable latency, per-call cap (→ `LocalSynthError.inputTooLong`) and hard failures.
final class FakeSynthHost: LocalSynthHost, @unchecked Sendable {
    struct Config {
        var latency: TimeInterval = 0
        /// Calls longer than this throw `inputTooLong` (exercise re-split).
        var maxCharsPerCall: Int? = nil
        /// Every call throws a non-overflow error (exercise Apple fallback).
        var failAlways = false
        var silence = false
        var sampleRate = 24_000
        var secondsPerChar = 0.05
        /// Behave like Kokoro's ONNX CPU route (may render while backgrounded).
        var rendersInBackground = false
    }

    struct FakeError: LocalizedError { var errorDescription: String? { "fake engine failure" } }

    let engineID: SpeechEngineID
    var routingLabel: String? { "fake" }
    var rendersInBackground: Bool { config.rendersInBackground }
    var routeTag: String? { config.rendersInBackground ? "onnx" : "coreml" }
    var onProgress: (@Sendable (Double) -> Void)?
    private let config: Config
    private let lock = NSLock()
    private var prepared = false
    private var _calls: [(text: String, ok: Bool)] = []

    init(engineID: SpeechEngineID, config: Config) {
        self.engineID = engineID
        self.config = config
    }

    var calls: [(text: String, ok: Bool)] { lock.withLock { _calls } }
    var isPrepared: Bool { lock.withLock { prepared } }

    func prepare() async throws {
        onProgress?(1)
        lock.withLock { prepared = true }
    }

    func synthesizeOnce(text: String, seed: UInt64) async throws -> SynthesizedPCM {
        if config.latency > 0 { try await Task.sleep(nanoseconds: UInt64(config.latency * 1e9)) }
        if config.failAlways {
            lock.withLock { _calls.append((text, false)) }
            throw FakeError()
        }
        if let cap = config.maxCharsPerCall, text.count > cap {
            lock.withLock { _calls.append((text, false)) }
            throw LocalSynthError.inputTooLong("fake cap \(cap) < \(text.count)")
        }
        lock.withLock { _calls.append((text, true)) }
        return SynthesizedPCM(samples: Self.tone(seconds: Double(text.count) * config.secondsPerChar,
                                                 sampleRate: config.sampleRate, silence: config.silence),
                              sampleRate: config.sampleRate)
    }

    func setVoice(_ voice: String) {}
    func resetPrepared() { lock.withLock { prepared = false } }
    func unload() async { resetPrepared() }

    static func tone(seconds: Double, sampleRate: Int, silence: Bool = false) -> [Float] {
        let n = max(1, Int(seconds * Double(sampleRate)))
        if silence { return [Float](repeating: 0, count: n) }
        return (0..<n).map { Float(sin(2 * Double.pi * 440 * Double($0) / Double(sampleRate)) * 0.1) }
    }
}

/// Registers one fake on-device engine (`test.fake`).
@MainActor
final class FakeEngineProvider: SpeechEngineProvider {
    static let fakeID = SpeechEngineID("test.fake")
    let name = "Fake"
    var config: FakeSynthHost.Config
    let limits: TextChunker.Limits
    private(set) var lastHost: FakeSynthHost?
    var installed = true
    /// Voices offered by the fake engine (voice picker / download-on-select tests).
    var voices: [EngineVoice] = []
    var defaultVoice: String?
    /// Languages the fake engine speaks (empty = any).
    var languages: [String] = []
    /// When set, `prepareVoice` throws it (voice download failure).
    var voiceDownloadError: Error?
    private(set) var preparedVoices: [String] = []

    init(config: FakeSynthHost.Config = .init(),
         limits: TextChunker.Limits = .init(target: 40, hardMax: 50, firstTarget: 30, minResplit: 10)) {
        self.config = config
        self.limits = limits
    }

    var descriptor: EngineDescriptor {
        EngineDescriptor(
            id: Self.fakeID, providerName: name, kind: .onDevice,
            displayName: "Fake (test)", shortName: "Fake", subtitle: "Test engine",
            isRecommended: false, sortOrder: 99,
            voices: voices, defaultVoiceID: defaultVoice, voiceDefaultsKey: nil, cacheVoiceKey: .prefixed("fake"),
            streaming: .wholeCall, limits: limits, limitNotes: "maxCharsPerCall",
            assets: [], approxDownloadBytes: 0, hardware: .none,
            computeRouting: nil, quirks: [], supportsBakeCache: true,
            crashGuarded: false, crashNoticeDetail: nil, supportedLanguages: languages)
    }

    var descriptors: [EngineDescriptor] { [descriptor] }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == Self.fakeID else { return nil }
        let host = FakeSynthHost(engineID: id, config: config)
        lastHost = host
        return host
    }

    /// Retired engines this fake provider declares (retirement cleanup tests).
    var retired: [RetiredEngine] = []
    var retiredEngines: [RetiredEngine] { retired }

    func isInstalled(_ id: SpeechEngineID) -> Bool { installed }
    func deleteModels(_ id: SpeechEngineID) throws { installed = false }

    func prepareVoice(_ voice: String, for id: SpeechEngineID) async throws {
        preparedVoices.append(voice)
        if let voiceDownloadError { throw voiceDownloadError }
    }
}

/// `SynthQueueContext` over a temp-dir cache and a fake engine (no coordinator, no FluidAudio).
@MainActor
final class FakeQueueContext: SynthQueueContext, SynthChunkRendering {
    let audioCache: ArticleAudioCache
    let root: URL
    let chunkRenderer: LocalChunkRenderer
    let host: FakeSynthHost
    var cacheEngineID: String { FakeEngineProvider.fakeID.rawValue }
    var activeChunkLimits: TextChunker.Limits { chunkRenderer.descriptor.limits }
    var synthRenderer: SynthChunkRendering { self }
    var engineShortName: String { "Fake" }

    /// (article key, paragraph, chunk) in render order.
    private(set) var renders: [(key: UUID, p: Int, c: Int)] = []
    private(set) var fallbackTexts: [String] = []
    private(set) var completed: [UUID] = []

    init(provider: FakeEngineProvider, runState: AppRunState = .shared) {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FakeTTSCache-\(UUID().uuidString)")
        audioCache = ArticleAudioCache(root: root)
        host = provider.makeHost(for: FakeEngineProvider.fakeID, voice: nil) as! FakeSynthHost
        // Private gate: the test host app may be warming a real engine on the shared gate.
        chunkRenderer = LocalChunkRenderer(host: host, descriptor: provider.descriptor, gate: SynthRenderGate(),
                                           runState: runState)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// Active cache voice (like the app's selected engine voice); nil = keep job voices as-is.
    var activeVoice: String?
    func normalizedCacheVoice(_ voiceID: String) -> String { activeVoice ?? voiceID }
    func fallbackAppleVoice(forCacheVoice voiceID: String) -> String? { nil }
    var activeRouteRendersInBackground: Bool { host.rendersInBackground }
    /// Article "playing" right now (background bake-ahead scope on the CPU route).
    var playingKey: UUID?
    var backgroundRenderCacheKey: UUID? { playingKey }
    func noteBakeMarksChanged() {}
    func bakeCompleted(cacheKey: UUID) { completed.append(cacheKey) }

    func renderChunkToFile(text: String, destination: URL, seed: UInt64, context: [String: Any]) async throws -> TimeInterval {
        // Context "key" is only a short prefix; recover the article UUID from the destination
        // path (<root>/<article uuid>/chunks/…) — the last UUID component (the Simulator's
        // device / app container ids come earlier in the path).
        let key = destination.pathComponents.compactMap(UUID.init(uuidString:)).last ?? UUID()
        renders.append((key, context["p"] as? Int ?? -1, context["c"] as? Int ?? -1))
        return try await chunkRenderer.renderChunk(text: text, to: destination, seed: seed, context: context)
    }

    /// Stand-in for Apple TTS (AVSpeechSynthesizer.write is unreliable in unit tests).
    func renderAppleFallback(text: String, destination: URL, rate: Float, voiceID: String?) async throws -> TimeInterval {
        fallbackTexts.append(text)
        let samples = FakeSynthHost.tone(seconds: Double(text.count) * 0.05, sampleRate: 24_000)
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: destination)
        return Double(samples.count) / 24_000
    }
}
