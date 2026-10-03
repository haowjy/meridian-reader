import XCTest
@testable import Reader

/// The engine that speaks is chosen once, when speaking starts, and keeps every command until the
/// next `speak` or stop. An on-device engine that finishes warming up mid-playback must not take
/// Pause / Resume / the play icon away from Apple's utterance.
@MainActor
final class EngineBindingTests: XCTestCase {
    private var cleanups: [() -> Void] = []
    private var sessionIDs: [UUID] = []

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
        // Stopping on the local engine files a gap-fill bake job in the process-wide store; another
        // test's coordinator would adopt it when its engine warms.
        for id in sessionIDs { BackgroundAudioBakeScheduler.shared.removePending(articleID: id) }
        sessionIDs = []
    }

    /// SpeechController over a scripted Apple engine + a fake on-device engine. Apple is selected,
    /// so the fake engine is cold until the test selects it (stands in for the launch warm-up
    /// finishing).
    private func makeSpeech() -> (SpeechController, LocalTTSCoordinator, FakeListenEngine) {
        let suite = "EngineBinding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), FakeEngineProvider()], gate: { _ in true })
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("EngineBinding-\(UUID().uuidString)")
        let guardDir = tmp.appendingPathComponent("EngineBindingGuard-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root),
                                              crashGuard: EngineCrashGuard(directory: guardDir))
        let apple = FakeListenEngine()
        let speech = SpeechController(engines: registry, localTTS: coordinator,
                                      audioSession: ListenAudioSession(managesSystemSession: false),
                                      nowPlaying: NowPlayingController(commandCenter: nil, infoCenter: nil),
                                      appleEngine: apple, resumePoints: nil)
        cleanups.append {
            speech.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: guardDir)
        }
        return (speech, coordinator, apple)
    }

    private func session() -> SpeechSession {
        let long = Array(repeating: "The first paragraph keeps the synthesizer busy for a good while.", count: 12)
            .joined(separator: " ")
        let id = UUID()
        sessionIDs.append(id)
        return SpeechSession(id: id,
                             document: ParagraphDocument(parts: [long, "The second paragraph.", "The third one."]),
                             detectedLanguage: "en", title: "Binding")
    }

    private func engineName(_ speech: SpeechController) -> String { speech.diagnostics.snapshot().engine }

    private func waitUntil(_ condition: () -> Bool, _ message: String) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), message)
    }

    func testWarmUpFinishingMidPlaybackLeavesAppleInChargeOfItsUtterance() async {
        let (speech, coordinator, apple) = makeSpeech()
        let s = session()
        speech.start(s, fromParagraph: 0)
        XCTAssertEqual(engineName(speech), "Apple")

        await coordinator.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(coordinator.usesLocalEngine)

        XCTAssertEqual(engineName(speech), "Apple", "Apple's utterance keeps its engine")
        XCTAssertFalse(speech.isBufferingNext, "Apple is speaking: nothing is buffering")
        speech.pause()
        XCTAssertEqual(apple.pauseCount, 1, "Pause went to Apple")
        XCTAssertEqual(engineName(speech), "Apple")
        XCTAssertEqual(speech.playback.phase, .paused)
    }

    func testPlayingSessionMovesToTheWarmEngineAtTheNextParagraph() async {
        let (speech, coordinator, apple) = makeSpeech()
        let s = session()
        speech.start(s, fromParagraph: 0)
        await coordinator.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertEqual(engineName(speech), "Apple")

        // Still in paragraph 0: Apple keeps going.
        apple.emit(.position(paragraph: 0, utf16: 40))
        XCTAssertEqual(engineName(speech), "Apple")

        // Apple starts speaking paragraph 1: the session switches there.
        let p1 = s.document.startUTF16Offset(forParagraph: 1)
        apple.emit(.position(paragraph: 1, utf16: p1))
        XCTAssertEqual(engineName(speech), "Fake", "switched to the warm engine at the paragraph start")
        XCTAssertGreaterThan(apple.stopCount, 0, "Apple stopped")
        XCTAssertEqual(speech.currentParagraphIndex, 1)
        XCTAssertEqual(speech.spokenUTF16Offset, p1)

        // A late callback from the replaced engine doesn't move the session.
        apple.emit(.finished)
        XCTAssertEqual(speech.playback.phase, .playing)
        XCTAssertNotNil(speech.activeSessionID)
        XCTAssertEqual(speech.playback.phase, .playing)
    }

    func testPausedSessionMovesToTheWarmEngineAtOnce() async {
        let (speech, coordinator, _) = makeSpeech()
        let s = session()
        speech.start(s, fromParagraph: 0)
        speech.pause()
        await coordinator.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertEqual(engineName(speech), "Fake", "nothing audible: rebinds at the paused spot")
        XCTAssertEqual(speech.playback.phase, .paused)
    }

    func testLeavingTheLocalEngineMidPlaybackStopsItsPlayer() async {
        let (speech, coordinator, apple) = makeSpeech()
        await coordinator.selectEngine(FakeEngineProvider.fakeID)
        let s = session()
        speech.start(s, fromParagraph: 0)
        XCTAssertEqual(engineName(speech), "Fake")
        await waitUntil({ speech.localEngine.player.isSpeaking }, "the local engine started")

        await coordinator.selectEngine(.apple)

        XCTAssertEqual(engineName(speech), "Apple")
        XCTAssertEqual(apple.plays.count, 1, "re-spoken with Apple at the playhead")
        XCTAssertFalse(speech.localEngine.player.isSpeaking, "the local player does not keep going unowned")
        XCTAssertEqual(speech.playback.phase, .playing)
    }

    func testLocalVoiceChangeRestartsTheUtteranceOnTheNewVoice() async {
        let (speech, coordinator, _) = makeSpeech()
        await coordinator.selectEngine(FakeEngineProvider.fakeID)
        speech.start(session(), fromParagraph: 0)
        await waitUntil({ speech.localEngine.player.isSpeaking }, "the local engine started")
        let before = speech.localEngine.player.debugEpoch

        coordinator.setVoice("v2", for: FakeEngineProvider.fakeID)

        XCTAssertGreaterThan(speech.localEngine.player.debugEpoch, before, "re-spoken in the new voice")
        XCTAssertEqual(engineName(speech), "Fake")
        XCTAssertEqual(speech.playback.phase, .playing)
    }

    // MARK: - Pure rules

    func testHandoverWaitsForTheParagraphOnlyWhileAppleIsAudible() {
        let kokoro = ListenRoute.local(.kokoro, voice: "af_heart")
        XCTAssertEqual(EngineHandover.decide(bound: .apple, wanted: .apple, phase: .playing), .none)
        XCTAssertEqual(EngineHandover.decide(bound: kokoro, wanted: kokoro, phase: .playing), .none)
        XCTAssertEqual(EngineHandover.decide(bound: .apple, wanted: kokoro, phase: .playing), .atNextParagraph)
        XCTAssertEqual(EngineHandover.decide(bound: .apple, wanted: kokoro, phase: .paused), .restartNow)
        XCTAssertEqual(EngineHandover.decide(bound: kokoro, wanted: .apple, phase: .playing), .restartNow)
        XCTAssertEqual(EngineHandover.decide(bound: kokoro, wanted: .local(.kokoro, voice: "bf_emma"), phase: .paused),
                       .restartNow)
    }

    func testEngineStateDerivesSelectionAndPersistence() {
        let task = Task<Void, Never> {}
        let warming = LocalEngineState.warming(.kokoro, progress: 0.4, task: task)
        XCTAssertEqual(warming.selectedEngineID, .kokoro)
        XCTAssertEqual(warming.activeEngineID, .kokoro)
        XCTAssertNil(warming.readyEngineID)
        XCTAssertEqual(warming.warmingProgress, 0.4)
        XCTAssertNil(warming.persistedSelection, "a load in flight keeps the last committed choice")

        XCTAssertEqual(LocalEngineState.ready(.kokoro).persistedSelection, .kokoro)
        XCTAssertEqual(LocalEngineState.ready(.kokoro).readyEngineID, .kokoro)

        let failed = LocalEngineState.failed(.kokoro, message: "no")
        XCTAssertEqual(failed.selectedEngineID, .apple)
        XCTAssertNil(failed.activeEngineID)
        XCTAssertEqual(failed.persistedSelection, .apple)
        XCTAssertEqual(LocalEngineState.off.selectedEngineID, .apple)
    }
}
