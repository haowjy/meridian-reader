import Foundation
@testable import MeridianReader

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
        /// Seconds per character in a voice set with `setVoice` (else `secondsPerChar`): a chunk's
        /// duration tells which voice rendered it. The voice is read when a call starts, as
        /// Kokoro's host does.
        var secondsPerCharByVoice: [String: Double] = [:]
        /// Behave like Kokoro's ONNX CPU route (may render while backgrounded).
        var rendersInBackground = false
        /// Calls (1-based, every call counted) that throw `engineUnavailable` and leave the host
        /// unprepared, as Kokoro's ONNX host does when rebuilding its session for a phase fails.
        var failingCalls: Set<Int> = []
        /// Counts the "sessions" hosts hold (one from each load until its unload), and, like an
        /// ORT session, a call in flight keeps its host's session alive past the unload.
        var sessions: FakeSessionCount? = nil
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
    private var _prepares = 0
    private var _calls: [(text: String, ok: Bool)] = []
    private var voice: String?
    private var _started = 0
    private var holdsSession = false
    private var callsInFlight = 0
    private var unloaded = false

    init(engineID: SpeechEngineID, config: Config) {
        self.engineID = engineID
        self.config = config
    }

    var calls: [(text: String, ok: Bool)] { lock.withLock { _calls } }
    /// Calls that have started (read their voice), finished or not.
    var startedCalls: Int { lock.withLock { _started } }
    var isPrepared: Bool { lock.withLock { prepared } }
    /// Loads, the first included.
    var prepares: Int { lock.withLock { _prepares } }

    func prepare() async throws {
        onProgress?(1)
        let opens: Bool = lock.withLock {
            prepared = true
            _prepares += 1
            defer { holdsSession = true }
            return !holdsSession
        }
        if opens { config.sessions?.open() }
    }

    func synthesizeOnce(text: String, priority: RenderPriority) async throws -> SynthesizedPCM {
        let secondsPerChar: Double = lock.withLock {
            _started += 1
            callsInFlight += 1
            return voice.flatMap { config.secondsPerCharByVoice[$0] } ?? config.secondsPerChar
        }
        defer {
            let closes: Bool = lock.withLock {
                callsInFlight -= 1
                return releaseSessionIfIdle()
            }
            if closes { config.sessions?.close() }
        }
        if config.latency > 0 { try await Task.sleep(nanoseconds: UInt64(config.latency * 1e9)) }
        let unloads: Bool = lock.withLock {
            guard config.failingCalls.contains(_calls.count + 1) else { return false }
            _calls.append((text, false))
            prepared = false
            return true
        }
        if unloads { throw LocalSynthError.engineUnavailable("fake session rebuild failed") }
        if config.failAlways {
            lock.withLock { _calls.append((text, false)) }
            throw FakeError()
        }
        if let cap = config.maxCharsPerCall, text.count > cap {
            lock.withLock { _calls.append((text, false)) }
            throw LocalSynthError.inputTooLong("fake cap \(cap) < \(text.count)")
        }
        lock.withLock { _calls.append((text, true)) }
        return SynthesizedPCM(samples: Self.tone(seconds: Double(text.count) * secondsPerChar,
                                                 sampleRate: config.sampleRate, silence: config.silence),
                              sampleRate: config.sampleRate)
    }

    func setVoice(_ voice: String) { lock.withLock { self.voice = voice } }

    func unload() async {
        let closes: Bool = lock.withLock {
            prepared = false
            unloaded = true
            return releaseSessionIfIdle()
        }
        if closes { config.sessions?.close() }
    }

    /// Called with `lock` held.
    private func releaseSessionIfIdle() -> Bool {
        guard unloaded, holdsSession, callsInFlight == 0 else { return false }
        holdsSession = false
        return true
    }

    static func tone(seconds: Double, sampleRate: Int, silence: Bool = false) -> [Float] {
        let n = max(1, Int(seconds * Double(sampleRate)))
        if silence { return [Float](repeating: 0, count: n) }
        return (0..<n).map { Float(sin(2 * Double.pi * 440 * Double($0) / Double(sampleRate)) * 0.1) }
    }
}

/// Live fake sessions across hosts, and the most ever live at once.
final class FakeSessionCount: @unchecked Sendable {
    private let lock = NSLock()
    private var live = 0
    private var _peak = 0

    var peak: Int { lock.withLock { _peak } }

    func open() { lock.withLock { live += 1; _peak = max(_peak, live) } }
    func close() { lock.withLock { live -= 1 } }
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
            id: Self.fakeID,
            displayName: "Fake (test)", shortName: "Fake", subtitle: "Test engine",
            sortOrder: 99,
            voices: voices, defaultVoiceID: defaultVoice, supportedLanguages: languages,
            onDevice: OnDeviceTraits(cacheVoicePrefix: "fake", limits: limits))
    }

    var descriptors: [EngineDescriptor] { [descriptor] }

    func makeHost(for id: SpeechEngineID, voice: String?) -> LocalSynthHost? {
        guard id == Self.fakeID else { return nil }
        let host = FakeSynthHost(engineID: id, config: config)
        if let voice { host.setVoice(voice) }
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
    let chunkPlans: ChunkPlans
    var synthRenderer: SynthChunkRendering { self }
    var engineShortName: String { "Fake" }

    /// (article key, paragraph, chunk, priority) in render order.
    private(set) var renders: [(key: UUID, p: Int, c: Int, priority: RenderPriority)] = []
    private(set) var fallbackTexts: [String] = []
    /// The Apple voice of each fallback render, in order.
    private(set) var fallbackVoices: [String?] = []
    private(set) var completed: [UUID] = []

    init(provider: FakeEngineProvider, runState: AppRunState = .shared) {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FakeTTSCache-\(UUID().uuidString)")
        audioCache = ArticleAudioCache(root: root)
        host = provider.makeHost(for: FakeEngineProvider.fakeID, voice: nil) as! FakeSynthHost
        let limits = provider.limits
        chunkPlans = ChunkPlans { $0 == FakeEngineProvider.fakeID.rawValue ? limits : nil }
        // Private gate: the test host app may be warming a real engine on the shared gate.
        chunkRenderer = LocalChunkRenderer(host: host, descriptor: provider.descriptor, gate: SynthRenderGate(),
                                           runState: runState)! // the fake engine is on-device
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    /// What renders (like the app's loaded engine in its selected voice); nil: no engine loaded.
    var renderTarget: RenderTarget? = RenderTarget(engineID: FakeEngineProvider.fakeID.rawValue, cacheVoice: "fake.default")
    /// The Apple voice the app would give for an article (the user's pick for its language).
    var appleVoice: String?
    func appleFallbackVoice(for paragraphs: [String]) -> String? { appleVoice }
    var activeRouteRendersInBackground: Bool { host.rendersInBackground }
    /// Article "playing" right now (listener priority; background bake-ahead scope on the CPU route).
    var playingCacheKey: UUID?
    /// Listening time ready ahead of the playhead, asked before each background bake-ahead chunk
    /// (0: none, so a background burst runs until nothing is left).
    var readyAhead: () -> TimeInterval = { 0 }
    func readyAheadSeconds(upTo limit: TimeInterval) -> TimeInterval { min(readyAhead(), limit) }
    func noteBakeMarksChanged() {}
    func bakeCompleted(cacheKey: UUID) { completed.append(cacheKey) }

    func renderChunkToFile(text: String, destination: URL, context: [String: Any],
                           priority: RenderPriority) async throws -> TimeInterval {
        // Context "key" is only a short prefix; recover the article UUID from the destination
        // path (<root>/<article uuid>/chunks/…) — the last UUID component (the Simulator's
        // device / app container ids come earlier in the path).
        let key = destination.pathComponents.compactMap(UUID.init(uuidString:)).last ?? UUID()
        renders.append((key, context["p"] as? Int ?? -1, context["c"] as? Int ?? -1, priority))
        return try await chunkRenderer.renderChunk(text: text, to: destination, context: context, priority: priority)
    }

    /// Stand-in for Apple TTS (AVSpeechSynthesizer.write is unreliable in unit tests).
    func renderAppleFallback(text: String, destination: URL, voiceID: String?) async throws -> TimeInterval {
        fallbackTexts.append(text)
        fallbackVoices.append(voiceID)
        let samples = FakeSynthHost.tone(seconds: Double(text.count) * 0.05, sampleRate: 24_000)
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: destination)
        return Double(samples.count) / 24_000
    }
}
