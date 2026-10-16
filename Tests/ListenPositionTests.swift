import XCTest
@testable import MeridianReader

/// The session owns the position. Engines report it (the on-device engine from player time,
/// through `ListenPositionMapper`), Pause turns the phase only once the engine confirms, and the
/// crash-resume point follows the session.
@MainActor
final class ListenPositionTests: XCTestCase {
    private var cleanups: [() -> Void] = []
    private var sessionIDs: [UUID] = []

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
        for id in sessionIDs { PendingBakeJobStore.shared.removePending(articleID: id) }
        sessionIDs = []
    }

    // MARK: - Mapper

    /// "First sentence here. " 0–20 · "Second sentence follows. " 21–45 · "Third one ends it." 46–63.
    private let text = "First sentence here. Second sentence follows. Third one ends it."
    private let chunks = ["First sentence here.", "Second sentence follows.", "Third one ends it."]

    func testMapperFindsTheChunkOfAScrubbedSentence() {
        let doc = ParagraphDocument(parts: ["Intro.", text])
        var mapper = ListenPositionMapper(document: doc) { [chunks] _ in chunks }
        let p1 = doc.startUTF16Offset(forParagraph: 1)

        let atStart = mapper.startPoint(utf16: p1)
        XCTAssertEqual(atStart.paragraph, 1)
        XCTAssertEqual(atStart.chunk, 0)
        XCTAssertEqual(atStart.fraction, 0)

        let second = mapper.startPoint(utf16: p1 + 21)
        XCTAssertEqual(second.chunk, 1)
        XCTAssertEqual(second.fraction, 0, accuracy: 1e-9)
        let inside = mapper.startPoint(utf16: p1 + 33)
        XCTAssertEqual(inside.chunk, 1)
        XCTAssertEqual(inside.fraction, 12.0 / 25.0, accuracy: 1e-9)
    }

    func testMapperTurnsPlayerTimeIntoTheDocumentSpot() {
        let doc = ParagraphDocument(parts: ["Intro.", text])
        var mapper = ListenPositionMapper(document: doc) { [chunks] _ in chunks }
        let p1 = doc.startUTF16Offset(forParagraph: 1)
        let file = URL(fileURLWithPath: "/unused.caf")

        let chunk = ChunkPlaybackQueue.Item(paragraphIndex: 1, fileURL: file, source: .chunk(1), duration: 2)
        XCTAssertEqual(mapper.position(of: chunk, time: 1, duration: 2)?.utf16, p1 + 21 + 12, "half of chunk 1")

        let baked = ChunkPlaybackQueue.Item(paragraphIndex: 1, fileURL: file, source: .baked, duration: 4,
                                                 chunkDurations: [1, 2, 1])
        XCTAssertEqual(mapper.position(of: baked, time: 3, duration: 4)?.utf16, p1 + 46, "chunk 2 starts at 3 s")

        let apple = ChunkPlaybackQueue.Item(paragraphIndex: 1, fileURL: file,
                                            source: .appleFallback(fromChunk: 1, reason: .behind), duration: 5)
        XCTAssertEqual(mapper.position(of: apple, time: 0, duration: 5)?.utf16, p1 + 21)
        XCTAssertNil(mapper.position(of: .init(paragraphIndex: 7, fileURL: file, source: .baked, duration: 1), time: 0, duration: 1))
    }

    // MARK: - Session

    func testPauseWaitsForTheEngineAndTheResumePointFollowsTheSession() {
        var s = PlaybackSessionState()
        let id = UUID()
        let doc = ParagraphDocument(parts: ["a.", "b.", "c."])
        s.bind(articleID: id, document: doc, at: ListenSpot(paragraph: 1))
        let silent = PlaybackEngineSnapshot(isAudible: false, isPaused: false)
        let audible = PlaybackEngineSnapshot(isAudible: true, isPaused: false)
        XCTAssertNil(s.resumePoint, "prepared: nothing to auto-play after a crash")

        XCTAssertEqual(s.handle(.play(from: 1), engine: silent), [.enginePlay])
        XCTAssertEqual(s.resumePoint, .init(article: id, paragraph: 1,
                                            text: ArticleIdentity.contentFingerprint(paragraphs: doc.paragraphs)))
        s.handle(.position(paragraph: 2, utf16: doc.startUTF16Offset(forParagraph: 2) + 1))
        XCTAssertEqual(s.playhead, 2)
        XCTAssertEqual(s.resumePoint?.paragraph, 2)

        XCTAssertEqual(s.handle(.pause, engine: audible), [.enginePause])
        XCTAssertEqual(s.phase, .playing, "not paused until the engine says so")
        s.handle(.becamePaused)
        XCTAssertEqual(s.phase, .paused)
        XCTAssertNil(s.resumePoint)
        XCTAssertEqual(s.handle(.pause, engine: PlaybackEngineSnapshot(isAudible: false, isPaused: true)), [],
                       "already held: nothing to send")
    }

    // MARK: - Controller

    private func makeSpeech(resumeFile: URL) -> (SpeechController, LocalTTSCoordinator, FakeListenEngine) {
        let suite = "ListenPosition-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), FakeEngineProvider()], gate: { _ in true })
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("ListenPosition-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root),
                                              crashGuard: EngineCrashGuard(directory: root.appendingPathComponent("guard")))
        let apple = FakeListenEngine()
        let speech = SpeechController(engines: registry, localTTS: coordinator,
                                      audioSession: ListenAudioSession(managesSystemSession: false),
                                      nowPlaying: NowPlayingController(commandCenter: nil, infoCenter: nil),
                                      appleEngine: apple, resumePoints: ListenResumePointStore(url: resumeFile))
        cleanups.append {
            speech.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: resumeFile)
        }
        return (speech, coordinator, apple)
    }

    private func session(_ parts: [String]) -> SpeechSession {
        let id = UUID()
        sessionIDs.append(id)
        return SpeechSession(id: id, document: ParagraphDocument(parts: parts), detectedLanguage: "en", title: "Position")
    }

    private func waitUntil(_ condition: () -> Bool, _ message: String) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), message)
    }

    func testTheResumeFileHoldsTheParagraphPlayingWhateverTheEngine() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID().uuidString).json")
        let store = ListenResumePointStore(url: file)
        let (speech, _, apple) = makeSpeech(resumeFile: file)
        let s = session(["One.", "Two.", "Three."])

        speech.start(s)
        XCTAssertEqual(store.load()?.paragraph, 0)
        XCTAssertTrue(store.load()?.matches(s.id) == true)
        XCTAssertEqual(store.load()?.text, ArticleIdentity.contentFingerprint(paragraphs: s.document.paragraphs),
                       "with the text it is a paragraph of")
        apple.emit(.position(paragraph: 1, utf16: s.document.startUTF16Offset(forParagraph: 1)))
        XCTAssertEqual(store.load()?.paragraph, 1)
        speech.pause()
        XCTAssertEqual(speech.playback.phase, .paused, "the engine confirmed")
        XCTAssertNil(store.load(), "paused: no auto-play after a crash")
        speech.resume()
        XCTAssertEqual(store.load()?.paragraph, 1)
        speech.stop()
        XCTAssertNil(store.load())
    }

    func testTheLocalEngineReportsPositionFromPlayerTimeFromTheScrubbedSentence() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID().uuidString).json")
        let (speech, coordinator, _) = makeSpeech(resumeFile: file)
        await coordinator.selectEngine(FakeEngineProvider.fakeID)
        let s = session([
            "Opening line.",
            "The first sentence of the second paragraph runs on a bit. Then the scrubbed sentence starts "
                + "here and keeps going for a while so the tone is long enough to move the thumb.",
        ])
        let target = s.document.startUTF16Offset(forParagraph: 1) + 58
        speech.start(s, at: ListenSpot(paragraph: 1, utf16Offset: target))
        XCTAssertEqual(speech.diagnostics.snapshot().engine, "Fake")

        await waitUntil({ speech.localEngine.player.state == .playing && speech.localEngine.player.isAudible },
                        "the first unit plays")
        XCTAssertEqual(speech.currentParagraphIndex, 1)
        XCTAssertGreaterThanOrEqual(speech.spokenUTF16Offset, target, "never before where the play began")
        let first = speech.spokenUTF16Offset

        await waitUntil({ speech.spokenUTF16Offset > first }, "the engine's clock moves the position")
        speech.pause()
        XCTAssertEqual(speech.playback.phase, .paused, "the local player confirms at once")
        XCTAssertGreaterThan(speech.spokenUTF16Offset, first)
    }
}
