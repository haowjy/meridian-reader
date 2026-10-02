import Observation
import XCTest
@testable import Reader

/// Views observe `SpeechController`'s published playback values one by one. The offset inside
/// a paragraph moves several times a second while playing; it must not redraw views that show
/// only the article, the phase or the paragraph.
@MainActor
final class PlaybackObservationTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        cleanups.reversed().forEach { $0() }
        cleanups = []
    }

    private func makeSpeech() -> SpeechController {
        let suite = "PlaybackObservation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider()], gate: { _ in true })
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("PlaybackObservation-\(UUID().uuidString)")
        let guardDir = tmp.appendingPathComponent("PlaybackObservationGuard-\(UUID().uuidString)")
        let coordinator = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                              audioCache: ArticleAudioCache(root: root),
                                              crashGuard: EngineCrashGuard(directory: guardDir))
        let speech = SpeechController(engines: registry, localTTS: coordinator,
                                      audioSession: ListenAudioSession(managesSystemSession: false),
                                      nowPlaying: NowPlayingController(commandCenter: nil, infoCenter: nil))
        cleanups.append {
            speech.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: guardDir)
        }
        return speech
    }

    private func session() -> SpeechSession {
        SpeechSession(id: UUID(),
                      document: ParagraphDocument(parts: ["First sentence here. Second sentence here.",
                                                          "Another paragraph.", "The last one."]),
                      detectedLanguage: "en")
    }

    /// True once any value read in `read` changes.
    private func tracks(_ read: @escaping () -> Void) -> () -> Bool {
        let flag = Flag()
        withObservationTracking(read) { flag.value = true }
        return { flag.value }
    }

    private final class Flag: @unchecked Sendable { var value = false }

    func testOffsetInsideParagraphRedrawsOnlyOffsetReaders() {
        let speech = makeSpeech()
        let s = session()
        speech.prepare(s)

        let coarse = tracks {
            _ = speech.activeSessionID
            _ = speech.document
            _ = speech.isPlaying
            _ = speech.currentParagraphIndex
            _ = speech.isPrepared(sessionID: s.id)
            _ = speech.canSkipToNextParagraph
            _ = speech.showsPauseIcon(for: s.id)
            _ = speech.isBufferingNext
            _ = speech.renderNote
        }
        let offset = tracks { _ = speech.spokenUTF16Offset }

        // Scrub to the second sentence of paragraph 0 while prepared: only the offset moves.
        speech.seek(s, toUTF16Offset: 21)

        XCTAssertEqual(speech.currentParagraphIndex, 0)
        XCTAssertEqual(speech.spokenUTF16Offset, 21)
        XCTAssertTrue(offset())
        XCTAssertFalse(coarse(), "an in-paragraph move must not invalidate article / phase / paragraph readers")
    }

    func testParagraphChangeRedrawsParagraphReadersOnly() {
        let speech = makeSpeech()
        let s = session()
        speech.prepare(s)

        let session = tracks { _ = speech.activeSessionID; _ = speech.isPlaying }
        let paragraph = tracks { _ = speech.currentParagraphIndex }

        speech.seek(s, toParagraph: 1)

        XCTAssertEqual(speech.currentParagraphIndex, 1)
        XCTAssertTrue(paragraph())
        XCTAssertFalse(session())
    }
}
