import AVFoundation
import XCTest
@testable import Reader

/// Background listening: remote commands → Session, interruptions / route changes, and the
/// foreground/background Core ML switch (fake engine; no model call may start in background).
@MainActor
final class BackgroundListeningTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
    }

    // MARK: - Helpers

    /// Real SpeechController + Session over the Apple engine, with a temp cache and no
    /// process-wide audio session / remote command registration.
    private func makeSpeech() -> (SpeechController, ListenAudioSession, NowPlayingController) {
        let suite = "BackgroundListening-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider()], gate: { _ in true })
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("BGListen-\(UUID().uuidString)")
        let guardDir = tmp.appendingPathComponent("BGListenGuard-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root),
                                              crashGuard: EngineCrashGuard(directory: guardDir))
        let audio = ListenAudioSession(managesSystemSession: false)
        let nowPlaying = NowPlayingController(commandCenter: nil, infoCenter: nil)
        let speech = SpeechController(engines: registry, localTTS: coordinator, audioSession: audio, nowPlaying: nowPlaying)
        let savedRate = UserDefaults.standard.object(forKey: "reader.rateMultiplier")
        cleanups.append {
            speech.stop()
            if let savedRate { UserDefaults.standard.set(savedRate, forKey: "reader.rateMultiplier") }
            else { UserDefaults.standard.removeObject(forKey: "reader.rateMultiplier") }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: guardDir)
        }
        return (speech, audio, nowPlaying)
    }

    private func session() -> SpeechSession {
        SpeechSession(id: UUID(),
                      document: ParagraphDocument(parts: ["First paragraph.", "Second paragraph.", "Third paragraph."]),
                      detectedLanguage: "en", title: "Remote Test", site: "example.com")
    }

    // MARK: - Remote commands → Session

    func testRemoteCommandsMapToSessionIntents() {
        XCTAssertEqual(RemoteCommand.play.intent, .resume)
        XCTAssertEqual(RemoteCommand.pause.intent, .pause)
        XCTAssertEqual(RemoteCommand.togglePlayPause.intent, .toggle)
        XCTAssertEqual(RemoteCommand.nextTrack.intent, .skip(delta: 1))
        XCTAssertEqual(RemoteCommand.previousTrack.intent, .skip(delta: -1))
        XCTAssertNil(RemoteCommand.changePlaybackRate(1.5).intent)

        // The Session decides (single source of truth) — deterministic engine snapshots.
        var s = PlaybackSessionState()
        s.bind(articleID: UUID(), document: ParagraphDocument(parts: ["a.", "b.", "c."]), startingAt: 0)
        let silent = PlaybackEngineSnapshot(isAudible: false, isPaused: false)
        let audible = PlaybackEngineSnapshot(isAudible: true, isPaused: false)
        let paused = PlaybackEngineSnapshot(isAudible: false, isPaused: true)
        XCTAssertEqual(s.handle(RemoteCommand.play.intent!, engine: silent), [.enginePlay(from: 0)])
        XCTAssertEqual(s.phase, .playing)
        XCTAssertEqual(s.handle(RemoteCommand.togglePlayPause.intent!, engine: audible), [.enginePause])
        XCTAssertEqual(s.phase, .paused)
        XCTAssertEqual(s.handle(RemoteCommand.play.intent!, engine: paused), [.engineResume])
        XCTAssertEqual(s.phase, .playing)
        XCTAssertEqual(s.handle(RemoteCommand.nextTrack.intent!, engine: audible), [.engineSeek(paragraph: 1)])
        XCTAssertEqual(s.playhead, 1)
        XCTAssertEqual(s.handle(RemoteCommand.previousTrack.intent!, engine: audible), [.engineSeek(paragraph: 0)])
        XCTAssertEqual(s.playhead, 0)
        XCTAssertEqual(s.handle(RemoteCommand.pause.intent!, engine: audible), [.enginePause])
        XCTAssertEqual(s.phase, .paused)
        XCTAssertEqual(s.handle(RemoteCommand.togglePlayPause.intent!, engine: paused), [.engineResume])
        XCTAssertEqual(s.phase, .playing)
    }

    func testRemoteCommandsDriveSpeechControllerSessionAndNowPlaying() {
        let (speech, audio, nowPlaying) = makeSpeech()
        XCTAssertEqual(speech.handleRemoteCommand(.play), .noActionableNowPlayingItem, "nothing prepared")

        let s = session()
        speech.prepare(s)
        XCTAssertNil(nowPlaying.lastInfo, "prepared but never played: no lock-screen item")
        XCTAssertFalse(audio.isActive)

        XCTAssertEqual(speech.handleRemoteCommand(.play), .success)
        XCTAssertEqual(speech.playback.phase, .playing)
        XCTAssertTrue(audio.isActive, "audio session activated when playback starts")
        XCTAssertEqual(nowPlaying.lastInfo?.title, "Remote Test")
        XCTAssertEqual(nowPlaying.lastInfo?.site, "example.com")
        XCTAssertEqual(nowPlaying.lastInfo?.progressLabel, "Paragraph 1 of 3")
        XCTAssertEqual(nowPlaying.lastInfo?.isPlaying, true)

        XCTAssertEqual(speech.handleRemoteCommand(.pause), .success)
        XCTAssertEqual(speech.playback.phase, .paused)
        XCTAssertEqual(nowPlaying.lastInfo?.isPlaying, false)

        XCTAssertEqual(speech.handleRemoteCommand(.nextTrack), .success)
        XCTAssertEqual(speech.currentParagraphIndex, 1)
        XCTAssertEqual(nowPlaying.lastInfo?.progressLabel, "Paragraph 2 of 3")
        XCTAssertEqual(speech.handleRemoteCommand(.nextTrack), .success)
        XCTAssertEqual(speech.currentParagraphIndex, 2)
        XCTAssertEqual(speech.handleRemoteCommand(.nextTrack), .commandFailed, "no paragraph after the last")
        XCTAssertEqual(speech.handleRemoteCommand(.previousTrack), .success)
        XCTAssertEqual(speech.currentParagraphIndex, 1)

        XCTAssertEqual(speech.handleRemoteCommand(.changePlaybackRate(1.4)), .success)
        XCTAssertEqual(speech.rateMultiplier, 1.5, "snapped to the nearest listen-bar rate")
        XCTAssertEqual(nowPlaying.lastInfo?.rate, 1.5)

        speech.stop() // Browse ✕
        XCTAssertNil(nowPlaying.lastInfo, "stop clears the lock screen")
        XCTAssertFalse(audio.isActive, "stop deactivates the session (other audio may resume)")
        XCTAssertEqual(speech.handleRemoteCommand(.play), .noActionableNowPlayingItem)
    }

    // MARK: - Interruptions / route changes

    func testInterruptionPolicy() {
        var p = ListenInterruptionPolicy()
        XCTAssertEqual(p.handle(.interruptionBegan, isPlaying: true), .pause)
        XCTAssertEqual(p.handle(.interruptionEnded(shouldResume: true), isPlaying: false), .resume)

        XCTAssertEqual(p.handle(.interruptionBegan, isPlaying: true), .pause)
        XCTAssertEqual(p.handle(.interruptionEnded(shouldResume: false), isPlaying: false), .none, "iOS said don't resume")

        XCTAssertEqual(p.handle(.interruptionBegan, isPlaying: false), .none)
        XCTAssertEqual(p.handle(.interruptionEnded(shouldResume: true), isPlaying: false), .none, "we weren't playing")

        XCTAssertEqual(p.handle(.interruptionBegan, isPlaying: true), .pause)
        p.noteUserIntent() // user paused / stopped meanwhile
        XCTAssertEqual(p.handle(.interruptionEnded(shouldResume: true), isPlaying: false), .none)

        XCTAssertEqual(p.handle(.oldDeviceUnavailable, isPlaying: true), .pause, "headphones unplugged")
        XCTAssertEqual(p.handle(.oldDeviceUnavailable, isPlaying: false), .none)
    }

    func testAudioSessionNotificationParsing() {
        let began: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        XCTAssertEqual(ListenAudioSession.interruptionEvent(began), .interruptionBegan)
        let endedResume: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ]
        XCTAssertEqual(ListenAudioSession.interruptionEvent(endedResume), .interruptionEnded(shouldResume: true))
        let ended: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
        XCTAssertEqual(ListenAudioSession.interruptionEvent(ended), .interruptionEnded(shouldResume: false))
        let unplug: [AnyHashable: Any] = [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
        XCTAssertEqual(ListenAudioSession.routeEvent(unplug), .oldDeviceUnavailable)
        let plugIn: [AnyHashable: Any] = [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]
        XCTAssertNil(ListenAudioSession.routeEvent(plugIn), "plugging headphones in doesn't pause")
    }

    func testInterruptionsPauseAndResumeTheSession() {
        let (speech, audio, _) = makeSpeech()
        speech.start(session(), fromParagraph: 0)
        XCTAssertEqual(speech.playback.phase, .playing)

        speech.handleAudioSessionEvent(.interruptionBegan) // call / Siri
        XCTAssertEqual(speech.playback.phase, .paused)
        speech.handleAudioSessionEvent(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(speech.playback.phase, .playing)
        XCTAssertTrue(audio.isActive, "session re-activated on resume")

        speech.handleAudioSessionEvent(.interruptionBegan)
        speech.handleAudioSessionEvent(.interruptionEnded(shouldResume: false))
        XCTAssertEqual(speech.playback.phase, .paused, "no shouldResume → stay paused")

        speech.handleRemoteCommand(.play)
        XCTAssertEqual(speech.playback.phase, .playing)
        speech.handleAudioSessionEvent(.oldDeviceUnavailable) // headphones out
        XCTAssertEqual(speech.playback.phase, .paused)
    }

    // MARK: - Background compute switch (fake engine)

    private var contexts: [FakeQueueContext] = []

    private func makeQueue(_ provider: FakeEngineProvider, runState: AppRunState) -> (GlobalSynthQueue, FakeQueueContext) {
        let ctx = FakeQueueContext(provider: provider, runState: runState)
        cleanups.append { ctx.cleanUp() }
        let queue = GlobalSynthQueue()
        queue.usesBackgroundGrace = false
        queue.runState = runState
        queue.attach(coordinator: ctx)
        return (queue, ctx)
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 20) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 30_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > timeout { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func sentence(_ n: Int) -> String {
        "Sentence number \(n) is here, and it runs on for a little while longer."
    }

    private func ensure(_ queue: GlobalSynthQueue, _ key: UUID, _ paras: [String], p: Int, c: Int) async throws
        -> GlobalSynthQueue.ChunkResolution {
        try await queue.ensureChunk(cacheKey: key, paragraphIndex: p, chunk: c, text: paras[p], paragraphs: paras,
                                    rate: 1, voiceID: "v", isEphemeral: false)
    }

    func testRendererRefusesModelCallInBackground() async {
        let state = AppRunState(phase: .background)
        let ctx = FakeQueueContext(provider: FakeEngineProvider(), runState: state)
        cleanups.append { ctx.cleanUp() }
        do {
            _ = try await ctx.chunkRenderer.renderChunk(text: "Hello there.", to: ctx.root.appendingPathComponent("x.caf"),
                                                        seed: 1, context: [:])
            XCTFail("expected deferredInBackground")
        } catch LocalSynthError.deferredInBackground {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(ctx.host.calls.isEmpty, "no model call started in the background")
    }

    func testBackgroundDefersLiveChunksAndHoldsBakeUntilForeground() async throws {
        let state = AppRunState(phase: .background)
        let (queue, ctx) = makeQueue(FakeEngineProvider(), runState: state)
        let key = UUID()
        let paras = [sentence(1), (2...4).map(sentence).joined(separator: " ")]
        queue.openArticle(cacheKey: key, paragraphs: paras, rate: 1, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.host.calls.isEmpty, "bake-ahead waits in the background")

        do {
            _ = try await ensure(queue, key, paras, p: 0, c: 0)
            XCTFail("expected deferredInBackground")
        } catch LocalSynthError.deferredInBackground {
            // producer → Apple TTS for this paragraph (never silent, never skipped)
        }
        XCTAssertEqual(queue.backgroundDeferrals, 1)
        XCTAssertTrue(ctx.host.calls.isEmpty)
        XCTAssertTrue(ctx.fallbackTexts.isEmpty, "no Apple audio written into the engine cache")

        state.set(.active) // back in the foreground → bake resumes
        try await waitIdle(queue)
        let expected = paras.flatMap(queue.chunkTexts(for:))
        XCTAssertEqual(ctx.host.calls.filter(\.ok).count, expected.count)
        for i in paras.indices {
            XCTAssertNotNil(ctx.audioCache.audioURL(articleID: key, paragraphIndex: i, engineID: ctx.cacheEngineID, voiceID: "v"))
        }
    }

    func testGoingToBackgroundMidBakeParksAfterInFlightChunkAndKeepsRenderedAudioPlayable() async throws {
        let state = AppRunState(phase: .active)
        let (queue, ctx) = makeQueue(FakeEngineProvider(config: .init(latency: 0.1)), runState: state)
        let key = UUID()
        let paras = [(1...4).map(sentence).joined(separator: " "), (5...7).map(sentence).joined(separator: " ")]
        let chunks0 = queue.chunkTexts(for: paras[0])
        XCTAssertGreaterThanOrEqual(chunks0.count, 4)
        queue.openArticle(cacheKey: key, paragraphs: paras, rate: 1, voiceID: "v", isEphemeral: false)

        let hash = ArticleIdentity.paragraphHash(paras[0])
        let c0 = ctx.audioCache.chunkURL(articleID: key, paragraphIndex: 0, textHash: hash, chunk: 0)
        let start = Date()
        while !ctx.audioCache.isUsableChunk(c0) {
            if Date().timeIntervalSince(start) > 10 { XCTFail("chunk 0 never rendered"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        state.set(.background) // user leaves the app
        try await waitIdle(queue)
        let callsAtPark = ctx.host.calls.count
        XCTAssertLessThan(callsAtPark, chunks0.count, "parked mid-paragraph (in-flight chunk only)")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(ctx.host.calls.count, callsAtPark, "no Core ML call while backgrounded")
        XCTAssertTrue(ctx.fallbackTexts.isEmpty, "background never writes Apple audio into the cache")

        // Already-rendered audio still plays in the background; unrendered is deferred.
        if case .chunk(let url) = try await ensure(queue, key, paras, p: 0, c: 0) {
            XCTAssertEqual(url, c0)
        } else {
            XCTFail("expected the rendered chunk")
        }
        do {
            _ = try await ensure(queue, key, paras, p: 1, c: 0)
            XCTFail("expected deferredInBackground")
        } catch LocalSynthError.deferredInBackground {}

        state.set(.active)
        try await waitIdle(queue)
        let expected = paras.flatMap(queue.chunkTexts(for:))
        XCTAssertEqual(ctx.host.calls.filter(\.ok).count, expected.count, "each chunk rendered once (none lost to the switch)")
        XCTAssertNotNil(ctx.audioCache.audioURL(articleID: key, paragraphIndex: 1, engineID: ctx.cacheEngineID, voiceID: "v"))
    }

    func testInactiveServesTheListenerButHoldsBakeAhead() async throws {
        let state = AppRunState(phase: .inactive) // Control Center / call banner
        let (queue, ctx) = makeQueue(FakeEngineProvider(), runState: state)
        let key = UUID()
        let paras = [sentence(1), sentence(2), sentence(3)]
        queue.openArticle(cacheKey: key, paragraphs: paras, rate: 1, voiceID: "v", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.isEmpty, "no bake-ahead while inactive")

        _ = try await ensure(queue, key, paras, p: 1, c: 0)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.renders.map { "\($0.p).\($0.c)" }, ["1.0"], "only the chunk a listener waits for")

        state.set(.active)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.host.calls.filter(\.ok).count, paras.flatMap(queue.chunkTexts(for:)).count)
    }

    // MARK: - ONNX CPU route (renders in the background)

    func testCPURouteKeepsRenderingPlayingArticleInBackgroundButHoldsOthers() async throws {
        let state = AppRunState(phase: .background)
        let (queue, ctx) = makeQueue(FakeEngineProvider(config: .init(rendersInBackground: true)), runState: state)
        let playing = UUID(), other = UUID()
        ctx.playingKey = playing
        let paras = [sentence(1), sentence(2), sentence(3)]
        let otherParas = [sentence(7), sentence(8)]
        queue.openArticle(cacheKey: other, paragraphs: otherParas, rate: 1, voiceID: "v", isEphemeral: false)
        queue.openArticle(cacheKey: playing, paragraphs: paras, rate: 1, voiceID: "v", isEphemeral: false)

        // Live chunk renders on the model (no Apple fallback, no deferral).
        if case .chunk = try await ensure(queue, playing, paras, p: 0, c: 0) {} else { XCTFail("expected a rendered chunk") }
        XCTAssertEqual(queue.backgroundDeferrals, 0)
        try await waitIdle(queue)
        for i in paras.indices {
            XCTAssertNotNil(ctx.audioCache.audioURL(articleID: playing, paragraphIndex: i, engineID: ctx.cacheEngineID, voiceID: "v"),
                            "bake of the playing article continues in the background")
        }
        XCTAssertFalse(ctx.renders.contains { $0.key == other }, "other articles wait for the foreground")
        XCTAssertTrue(ctx.fallbackTexts.isEmpty)

        state.set(.active)
        try await waitIdle(queue)
        XCTAssertTrue(ctx.renders.contains { $0.key == other }, "foreground resumes everything")
    }
}
