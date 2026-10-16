import SwiftData
import XCTest
@testable import MeridianReader

/// Crash resume applies the paragraph that was playing only on a page holding the text it was
/// played in; otherwise the page opens paused at its own spot and keeps it. Each test runs the
/// app's pieces as the app wires them: the real `SpeechController` writing a resume file in a
/// temporary directory, the `ListeningProgressRecorder`, a file-backed library. Kokoro then
/// crashes, the next launch reads that file as the coordinator does (`KokoroCrashRecovery`) and
/// runs `AppLaunch.launch`, and each test ends with one more relaunch.
@MainActor
final class CrashResumeFollowsTextTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var recorder: ListeningProgressRecorder?
    private var shell = ShellState()
    private let notifications = NotificationCenter()
    private var resumePoints: ListenResumePointStore { env.speech.resumePoints }
    private var speech: SpeechController { env.speech.speech }
    private var library: LibraryStore { env.library }

    override func setUp() async throws {
        env = try LibraryTestEnvironment(fileBacked: true)
        startApp()
    }

    override func tearDown() async throws {
        recorder = nil
        env.cleanUp()
    }

    /// The controller, writing the resume file, and the recorder, as `AppComposition` wires them.
    private func startApp() {
        recorder = ListeningProgressRecorder(speech: speech, library: env.library, notificationCenter: notifications)
        shell = ShellState()
    }

    // MARK: - Helpers

    private let url = "https://example.com/story"
    private let firstText = ["The story starts here.", "It carries on a while.", "It turns a corner.", "It ends here."]
    /// `firstText` refreshed: two paragraphs come in after the second.
    private let secondText = ["The story starts here.", "It carries on a while.", "A paragraph that wasn't there.",
                              "Another one after it.", "It turns a corner.", "It ends here."]

    private struct Spot: Equatable {
        var paragraph: Int
        var utf16: Int
    }

    private func spot(_ page: Page?) -> Spot? {
        page.map { Spot(paragraph: $0.positionParagraph, utf16: $0.positionUTF16) }
    }

    private var sessionSpot: Spot { Spot(paragraph: speech.currentParagraphIndex, utf16: speech.spokenUTF16Offset) }

    private func fingerprint(_ paragraphs: [String]) -> String {
        ArticleIdentity.contentFingerprint(paragraphs: paragraphs)
    }

    /// A row's ▶ on `page`, as `LibraryActions.play` does it.
    private func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.start(.page(page), at: page.listenStart)
        }
    }

    /// Playback reaches `paragraph` of the text it plays, `into` UTF-16 units past its start;
    /// returns the spot.
    @discardableResult
    private func listen(to paragraph: Int, into: Int = 0) -> Spot {
        let at = speech.document.startUTF16Offset(forParagraph: paragraph) + into
        env.speech.apple.emit(.position(paragraph: paragraph, utf16: at))
        return Spot(paragraph: paragraph, utf16: at)
    }

    /// The page at `url` extracted again with `paragraphs` and resolved against the library, as
    /// opening it in the Reader does: a page holding other text is refreshed.
    private func open(_ paragraphs: [String]) {
        _ = library.readerArticle(url: URL(string: url)!, extracted: env.article(url, paragraphs: paragraphs).extracted)
    }

    /// Kokoro crashes while rendering `paragraph` of `key`: the process dies, so nothing more is
    /// written, and the next launch's coordinator reads the resume file (`KokoroCrashRecovery`,
    /// as `LocalTTSCoordinator` does at init) and keeps the target for the launch. The stores
    /// are opened again from disk, with a new controller and recorder. Returns the target.
    @discardableResult
    private func crash(rendering key: UUID, paragraph: Int) throws -> ListenResumeTarget {
        let marker = EngineCrashGuard.CrashInfo(engine: .kokoro, route: KokoroRoute.onnxCPU.rawValue,
                                                articleKey: key.uuidString, paragraph: paragraph, phase: "foreground",
                                                at: Date())
        let recovery = KokoroCrashRecovery.recover(from: marker, playing: resumePoints.load(),
                                                   settings: KokoroRouteSettings(defaults: env.defaults))
        let target = try XCTUnwrap(recovery.resume, "Kokoro resumes after an ONNX crash")
        recorder = nil
        try env.relaunch()
        startApp()
        speech.localTTS.pendingResume = target
        return target
    }

    /// The launch sequence, crash resume included.
    private func launch() async {
        await AppLaunch.launch(library: library, speech: speech, shell: shell,
                               importFiles: BookImportFiles(directory: env.dir.appending(path: "Imports")))
    }

    /// Quitting and opening the app again, with no crash.
    private func relaunch() throws {
        recorder = nil
        try env.relaunch()
        startApp()
    }

    /// The resume file as a build before text fingerprints wrote it: key, paragraph, time.
    private func writeOlderResumeFile(key: UUID, paragraph: Int) throws {
        let json: [String: Any] = ["article": key.uuidString, "p": paragraph, "t": Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject: json).write(to: resumePoints.url, options: .atomic)
    }

    // MARK: - The text that played

    /// A page plays its text to paragraph 2 while saves fail, so the store still holds paragraph
    /// 1 when Kokoro crashes. The page holds the text the resume file names: the launch plays it
    /// again at paragraph 2, and that is stored. A relaunch agrees.
    func testACrashResumesThePageHoldingTheTextThatPlayedAtTheParagraphPlaying() async throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        play(page)
        let stored = listen(to: 1)
        library.saveContext = { _ in throw CocoaError(.fileWriteNoPermission) }
        listen(to: 2)
        XCTAssertEqual(resumePoints.load()?.paragraph, 2, "the resume file holds the paragraph playing")
        XCTAssertEqual(resumePoints.load()?.text, fingerprint(firstText), "and the text it is in")

        let target = try crash(rendering: key, paragraph: 3)
        XCTAssertTrue(target.autoPlay)
        XCTAssertEqual(spot(library.page(key: key)), stored, "the store lagged behind the playhead")
        await launch()

        let reopened = try XCTUnwrap(library.page(key: key))
        XCTAssertEqual(speech.activeSessionID, key)
        XCTAssertTrue(shell.isNowPlayingPresented, "in Now Playing")
        XCTAssertEqual(speech.playbackPhase, .playing, "playing again")
        let resumed = Spot(paragraph: 2, utf16: speech.document.startUTF16Offset(forParagraph: 2))
        XCTAssertEqual(sessionSpot, resumed, "at the paragraph that was playing")
        XCTAssertEqual(spot(reopened), resumed, "and stored")

        try relaunch()
        XCTAssertEqual(spot(library.page(key: key)), resumed, "after a relaunch")
    }

    /// p152's sequence: a saved page plays; opening it again refreshes its text while the older
    /// session plays on (nothing it reaches is written on the page) to paragraph 3, and the
    /// resume file names that paragraph of the older text. Kokoro crashes. The launch finds the
    /// key holding the refreshed text: it opens the page in Now Playing paused at its own spot,
    /// writes nothing on it, and doesn't play. ▶ then plays the refreshed text from there, and
    /// that is recorded. A relaunch agrees.
    func testACrashAfterThePagesTextChangedOpensItPausedAtItsOwnSpot() async throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        play(page)
        let heard = listen(to: 1, into: 3)
        let startedAt = try XCTUnwrap(page.lastPlayedAt)
        open(secondText)
        XCTAssertEqual(page.cachedListenParagraphs, secondText, "refreshed on open")
        XCTAssertEqual(speech.document.paragraphs, firstText, "the session plays on in the text it was bound with")
        listen(to: 3)
        XCTAssertEqual(spot(page), heard, "nothing in the older text is written on the page")
        XCTAssertEqual(resumePoints.load()?.paragraph, 3)
        XCTAssertEqual(resumePoints.load()?.text, fingerprint(firstText))
        env.now += 60

        let target = try crash(rendering: key, paragraph: 3)
        XCTAssertTrue(target.autoPlay, "the crash just happened")
        await launch()

        let reopened = try XCTUnwrap(library.page(key: key))
        XCTAssertEqual(reopened.cachedListenParagraphs, secondText)
        XCTAssertEqual(speech.activeSessionID, key, "the page opens")
        XCTAssertTrue(shell.isNowPlayingPresented, "in Now Playing")
        XCTAssertEqual(speech.document.paragraphs, secondText, "in the text it holds")
        XCTAssertEqual(speech.playbackPhase, .prepared, "paused")
        XCTAssertEqual(sessionSpot, heard, "at its own spot, not the older text's paragraph 3")
        XCTAssertEqual(spot(reopened), heard, "which it keeps")
        XCTAssertEqual(reopened.lastPlayedAt, startedAt, "no start")

        play(reopened)
        XCTAssertEqual(speech.playbackPhase, .playing)
        XCTAssertEqual(sessionSpot, heard, "▶ plays from its own spot")
        let next = listen(to: 2)
        XCTAssertEqual(spot(reopened), next, "the refreshed text's listening is recorded")

        try relaunch()
        let again = try XCTUnwrap(library.page(key: key))
        XCTAssertEqual(again.cachedListenParagraphs, secondText, "after a relaunch")
        XCTAssertEqual(spot(again), next, "after a relaunch")
    }

    // MARK: - A resume file an older build wrote

    /// The resume file names no text: it is the older build's. It names the page's own stored
    /// paragraph, so it holds nothing the page doesn't: the launch plays the page again there.
    func testAnOlderResumeFileNamingThePagesOwnParagraphResumesThere() async throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        play(page)
        listen(to: 2)
        try writeOlderResumeFile(key: key, paragraph: 2)

        let target = try crash(rendering: key, paragraph: 3)
        XCTAssertNil(target.text, "an older file names no text")
        XCTAssertTrue(target.autoPlay)
        await launch()

        XCTAssertEqual(speech.activeSessionID, key)
        XCTAssertEqual(speech.playbackPhase, .playing, "playing again")
        XCTAssertEqual(speech.currentParagraphIndex, 2, "at that paragraph")
        XCTAssertEqual(library.page(key: key)?.positionParagraph, 2)
    }

    /// The older file names a paragraph other than the page's stored one (the store lagged, or
    /// the page holds other text by now: nothing tells which). The paragraph isn't applied: the
    /// page opens paused at its own spot, and keeps it. A relaunch agrees.
    func testAnOlderResumeFileNamingAnotherParagraphOpensThePagePausedAtItsOwnSpot() async throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        play(page)
        let heard = listen(to: 1, into: 4)
        try writeOlderResumeFile(key: key, paragraph: 3)

        let target = try crash(rendering: key, paragraph: 3)
        XCTAssertNil(target.text)
        XCTAssertEqual(target.paragraph, 3)
        await launch()

        XCTAssertEqual(speech.activeSessionID, key, "the page opens")
        XCTAssertTrue(shell.isNowPlayingPresented)
        XCTAssertEqual(speech.playbackPhase, .prepared, "paused")
        XCTAssertEqual(sessionSpot, heard, "at its own spot")
        XCTAssertEqual(spot(library.page(key: key)), heard, "which it keeps")

        try relaunch()
        XCTAssertEqual(spot(library.page(key: key)), heard, "after a relaunch")
    }
}
