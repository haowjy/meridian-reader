import SwiftData
import UIKit
import XCTest
@testable import MeridianReader

/// Listening progress lands only on the text that was played: a start, a position or an end is
/// stored on a page only while that page holds the text the session plays, a rollback writes it
/// again only on a page holding that text, and a session follows a merged key only onto a page
/// holding its text (otherwise it stops). Each test runs the app's pieces as the app wires them
/// (the real `SpeechController`, `ListeningProgressRecorder` and a file-backed library) and ends
/// with a relaunch.
@MainActor
final class ProgressFollowsTextTests: XCTestCase {
    private var fixture: TestSpeech!
    private var env: LibraryTestEnvironment!
    private var recorder: ListeningProgressRecorder?
    private let notifications = NotificationCenter()
    private var speech: SpeechController { fixture.speech }
    private var library: LibraryStore { env.library }
    /// The merges reported to the session (`keyMerged`), in order.
    private var merged: [[UUID]] = []

    override func setUp() async throws {
        fixture = TestSpeech()
        env = try LibraryTestEnvironment(fileBacked: true)
        recorder = ListeningProgressRecorder(speech: fixture.speech, library: env.library,
                                             notificationCenter: notifications)
        // As `AppComposition` wires them.
        library.stopPlaybackIfPlaying = { [unowned self] key in
            if speech.activeSessionID == key { speech.stop() }
        }
        library.keyMerged = { [unowned self] from, to, text in
            merged.append([from, to])
            speech.rekeyActiveSession(from: from, to: to, text: text)
        }
        speech.nextChapters = env.library
    }

    override func tearDown() async throws {
        recorder = nil
        fixture.tearDown()
        env.cleanUp()
    }

    private struct SaveFailed: Error {}
    private func failSaves() { library.saveContext = { _ in throw SaveFailed() } }
    private func allowSaves() { library.saveContext = { try $0.save() } }

    /// Stopping the recorder and reopening the stores, as a relaunch does.
    private func relaunch() throws {
        recorder = nil
        try env.relaunch()
    }

    // MARK: - Helpers

    private let bookKey = UUID()
    private let one = UUID(), two = UUID(), three = UUID(), renamed = UUID(), five = UUID()
    private let textOne = ["One begins.", "One goes on.", "One ends."]
    private let textTwo = ["Two begins.", "Two goes on.", "Two ends."]
    private let editedTwo = ["Two begins.", "Two goes on, differently now.", "Two ends."]
    private let textThree = ["Three begins.", "Three goes on.", "Three ends."]
    /// Other text that comes under a key `textThree` was under.
    private let textNew = ["A new chapter opens.", "It takes its own way.", "And it closes."]

    private var details: FolderDetails {
        FolderDetails(kind: .book, title: "The Book", byline: "Ada Example", cover: nil, sourceURL: nil,
                      sourceIdentifier: bookKey.uuidString, sourceState: nil)
    }

    private func chapter(_ key: UUID, _ ordinal: Int, _ title: String, _ paragraphs: [String]) -> PageContent {
        let ref = PageRef(key: key, locator: .book(EPUBLocator(href: "OEBPS/c\(ordinal).xhtml", anchor: .fileStart)),
                          ordinal: ordinal, title: title, skipsInPlayback: false)
        return PageContent(ref: ref, title: title, bodyHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                           plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
    }

    private func replace(_ book: Folder, _ chapters: [PageContent]) throws {
        try library.replaceBook(book, with: details, chapters: chapters)
    }

    /// A row's ▶ on `page`, as `LibraryActions.play` does it: pauses, resumes or starts it.
    private func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.start(.page(page), at: page.listenStart)
        }
    }

    /// Playback reaches `paragraph` of the text it plays; returns the spot.
    @discardableResult
    private func listen(to paragraph: Int) -> Spot {
        let start = speech.document.startUTF16Offset(forParagraph: paragraph)
        fixture.apple.emit(.position(paragraph: paragraph, utf16: start))
        return Spot(paragraph: paragraph, utf16: start)
    }

    /// The engine plays the bound page to its end.
    private func finish() {
        listen(to: speech.document.count - 1)
        fixture.apple.emit(.finished)
    }

    private struct Spot: Equatable {
        var paragraph: Int
        var utf16: Int
    }

    private func spot(_ page: Page?) -> Spot? {
        page.map { Spot(paragraph: $0.positionParagraph, utf16: $0.positionUTF16) }
    }

    private var audioWorkKinds: [LibraryAudioWorkKind?] {
        ((try? env.context.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))) ?? []).map(\.kind)
    }

    /// The waiting audio work is let through and runs with an unrelated save.
    private func runWaitingWork() throws {
        env.cache.faultHook = nil
        _ = try library.save(env.article("https://example.com/elsewhere"))
        XCTAssertTrue(audioWorkKinds.isEmpty, "the waiting work ran and is retired")
    }

    /// Chapter three plays to paragraph 1; a Replace edits chapter two and finds three's text
    /// under `renamed`, carrying the spot there. Aligning two's audio fails, so the merge that
    /// moves three's session onto `renamed` waits, and the session plays on under key three.
    /// Every audio step fails until `runWaitingWork`.
    private func playThreeWhileItsMergeWaits() throws -> (book: Folder, carried: Spot) {
        let book = try library.addBook(details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                           chapter(three, 2, "Three", textThree)], in: nil)
        try env.storeAudio(two, paragraphs: textTwo)
        try env.storeAudio(three, paragraphs: textThree)
        play(try XCTUnwrap(library.page(key: three)))
        let carried = listen(to: 1)
        env.cache.faultHook = { _ in throw SaveFailed() }
        try replace(book, [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo),
                           chapter(renamed, 2, "Three", textThree)])
        XCTAssertEqual(audioWorkKinds, [.align, .merge], "the merge waits behind the align")
        XCTAssertEqual(speech.activeSessionID, three, "the session plays on under the merged key")
        XCTAssertEqual(spot(library.page(key: renamed)), carried, "its spot is carried")
        return (book, carried)
    }

    // MARK: - A key that comes back with other text

    /// Chapter three plays while its merge into `renamed` waits. A second Replace keeps `renamed`
    /// and brings key three back with other text, which neither revises nor drops a chapter, so
    /// nothing stops the session: it plays on, in the old text, under a key the new chapter now
    /// holds. Nothing it reaches is written on that chapter (its spot, start and end stay its
    /// own), nor on the book; and once the waiting merge runs, it leaves key three to that chapter
    /// and moves no session. A relaunch agrees.
    func testASessionPlayingOnThroughAReplaceThatBringsItsKeyBackWritesNothingOnTheNewChapter() throws {
        let (book, carried) = try playThreeWhileItsMergeWaits()
        try replace(book, [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo),
                           chapter(renamed, 2, "Three", textThree), chapter(three, 3, "Three again", textNew)])
        let back = try XCTUnwrap(library.page(key: three))
        XCTAssertEqual(back.cachedListenParagraphs, textNew, "key three is back, with other text")
        XCTAssertEqual(speech.activeSessionID, three, "the session plays on")
        XCTAssertEqual(speech.document.paragraphs, textThree, "in the text it was bound with")

        listen(to: 2)
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        finish()
        XCTAssertEqual(speech.playbackPhase, .finished, "the old text played to its end")
        XCTAssertEqual(spot(back), Spot(paragraph: 0, utf16: 0), "no position in the old text on the new chapter")
        XCTAssertNil(back.lastPlayedAt, "no start")
        XCTAssertNil(back.finishedAt, "and no end: the new chapter wasn't heard")
        XCTAssertEqual(spot(library.page(key: renamed)), carried, "the moved chapter keeps its spot")

        try runWaitingWork()
        XCTAssertTrue(merged.isEmpty, "the merge leaves key three to the chapter holding it")

        try relaunch()
        let reopened = try XCTUnwrap(env.library.page(key: three))
        XCTAssertEqual(spot(reopened), Spot(paragraph: 0, utf16: 0), "after a relaunch")
        XCTAssertNil(reopened.lastPlayedAt, "after a relaunch")
        XCTAssertNil(reopened.finishedAt, "after a relaunch")
        XCTAssertNil(env.library.book(key: bookKey)?.finishedAt, "after a relaunch")
        XCTAssertEqual(spot(env.library.page(key: renamed)), carried, "after a relaunch")
    }

    /// The A→B→C chain: chapter three's text moves to `renamed` (its merge waits) and on to
    /// `five` (a second merge waits), and a third Replace brings key `renamed` back with other
    /// text. None of these revises or drops the text playing, so the session on key three plays
    /// on. When the work runs, the first merge finds no page under key three and moves its audio
    /// onto `renamed`, which holds other text now: the session isn't moved there but stops, and
    /// nothing in the old text is written on `renamed`. `five`, which holds the text that played,
    /// keeps the spot carried to it. A relaunch agrees.
    func testAMergeOntoAKeyThatCameBackWithOtherTextStopsTheSessionRatherThanMovingIt() throws {
        let (book, carried) = try playThreeWhileItsMergeWaits()
        let withFive = [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo), chapter(five, 2, "Three", textThree)]
        try replace(book, withFive)
        XCTAssertEqual(audioWorkKinds, [.align, .merge, .merge], "both merges wait")
        try replace(book, withFive + [chapter(renamed, 3, "Renamed again", textNew)])
        XCTAssertEqual(library.page(key: renamed)?.cachedListenParagraphs, textNew, "key renamed is back, with other text")
        XCTAssertEqual(speech.activeSessionID, three, "the session plays on")

        try runWaitingWork()
        XCTAssertEqual(merged, [[three, renamed]], "the first merge reports key three merged into renamed")
        XCTAssertNil(speech.activeSessionID, "the session playing the old text stops rather than moving onto renamed")
        XCTAssertNil(speech.nowPlaying)
        let back = try XCTUnwrap(library.page(key: renamed))
        fixture.apple.emit(.position(paragraph: 2, utf16: ParagraphDocument(parts: textThree).utf16Ranges[2].location))
        XCTAssertEqual(spot(back), Spot(paragraph: 0, utf16: 0), "nothing in the old text is written on renamed")
        XCTAssertNil(back.lastPlayedAt)
        XCTAssertEqual(spot(library.page(key: five)), carried, "the text that played keeps its spot under five")

        try relaunch()
        XCTAssertEqual(spot(env.library.page(key: renamed)), Spot(paragraph: 0, utf16: 0), "after a relaunch")
        XCTAssertNil(env.library.page(key: renamed)?.lastPlayedAt, "after a relaunch")
        XCTAssertEqual(spot(env.library.page(key: five)), carried, "after a relaunch")
    }

    // MARK: - A session older than its page

    private let url = "https://example.com/story"
    private let firstText = ["The story starts here, at some length.", "It carries on a while.",
                             "It turns a corner.", "It ends here."]
    private let secondText = ["The story starts differently now.", "It carries on a while.",
                              "A paragraph that wasn't there.", "It turns a corner.", "It ends here."]

    /// The page at `url` with `paragraphs`, extracted again and resolved against the library, as
    /// opening it in the Reader does: a page holding other text is refreshed.
    @discardableResult
    private func open(_ paragraphs: [String]) -> ReaderArticle {
        library.readerArticle(url: URL(string: url)!, extracted: env.article(url, paragraphs: paragraphs).extracted)
    }

    /// A resumed session older than its page: a saved page plays and is paused; opening it again
    /// refreshes its text. ▶ resumes the session bound before, which plays its own (older)
    /// document: nothing it reaches is written on the page, not on leaving the app, not when
    /// Listen on the refreshed article plays that older document on, not at its end. The page
    /// keeps its spot, its start and its unfinished state. A relaunch agrees.
    func testAResumedSessionOlderThanItsRefreshedPageWritesNothingOnIt() throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        play(page)
        let heard = listen(to: 1)
        speech.pause()
        let startedAt = try XCTUnwrap(page.lastPlayedAt)
        env.now += 60

        let refreshed = open(secondText)
        XCTAssertEqual(page.cachedListenParagraphs, secondText, "refreshed on open")
        XCTAssertEqual(speech.document.paragraphs, firstText, "the session keeps the text it was bound with")

        play(page)
        XCTAssertEqual(speech.playbackPhase, .playing, "▶ resumes it")
        listen(to: 2)
        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        speech.pause()
        speech.listen(to: refreshed, at: ListenSpot(paragraph: 3))
        XCTAssertEqual(speech.document.paragraphs, firstText, "Listen plays the session bound, in its own text")
        finish()
        XCTAssertEqual(spot(page), heard, "nothing in the older text is written on the refreshed page")
        XCTAssertEqual(page.lastPlayedAt, startedAt, "no start")
        XCTAssertNil(page.finishedAt, "no end")

        try relaunch()
        let reopened = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(reopened.cachedListenParagraphs, secondText)
        XCTAssertEqual(spot(reopened), heard, "after a relaunch")
        XCTAssertEqual(reopened.lastPlayedAt, startedAt, "after a relaunch")
        XCTAssertNil(reopened.finishedAt, "after a relaunch")
    }

    /// A staged chapter older than its page: chapter one plays with chapter two staged behind it
    /// (as `stageNextChapterIfDue` stages it on the on-device route), and a Replace revises
    /// chapter two, which isn't playing, so nothing stops. Playback carries on into the staged
    /// session, two's older text: no start, position or end of it is written on the revised
    /// chapter, and the book's place doesn't move to it. Carrying on into chapter three, loaded
    /// as it is, records as always. A relaunch agrees.
    func testAStagedChapterOlderThanItsRevisedPageWritesNothingOnIt() throws {
        let book = try library.addBook(details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                           chapter(three, 2, "Three", textThree)], in: nil)
        play(try XCTUnwrap(library.page(key: one)))
        speech.chapterFlow.stagedAfter = one
        speech.chapterFlow.nextSession = library.load(two)
        try replace(book, [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo),
                           chapter(three, 2, "Three", textThree)])
        XCTAssertEqual(speech.activeSessionID, one, "chapter one plays on")

        finish()
        XCTAssertEqual(speech.activeSessionID, two, "playback carried on into chapter two")
        XCTAssertEqual(speech.document.paragraphs, textTwo, "as staged, in its older text")
        let revised = try XCTUnwrap(library.page(key: two))
        XCTAssertNotNil(library.page(key: one)?.finishedAt, "chapter one, carried past, is finished")
        listen(to: 1)
        finish()
        XCTAssertEqual(speech.activeSessionID, three, "and on into chapter three")
        XCTAssertEqual(spot(revised), Spot(paragraph: 0, utf16: 0), "no position in the older text on the revised chapter")
        XCTAssertNil(revised.lastPlayedAt, "no start")
        XCTAssertNil(revised.finishedAt, "no end")
        let heard = listen(to: 1)
        XCTAssertEqual(spot(library.page(key: three)), heard, "chapter three records as always")
        XCTAssertEqual(book.currentPageKey, three, "and is the book's place")

        try relaunch()
        XCTAssertNotNil(env.library.page(key: one)?.finishedAt, "after a relaunch")
        let reopened = try XCTUnwrap(env.library.page(key: two))
        XCTAssertEqual(spot(reopened), Spot(paragraph: 0, utf16: 0), "after a relaunch")
        XCTAssertNil(reopened.lastPlayedAt, "after a relaunch")
        XCTAssertNil(reopened.finishedAt, "after a relaunch")
        XCTAssertEqual(spot(env.library.page(key: three)), heard, "after a relaunch")
        XCTAssertEqual(env.library.book(key: bookKey)?.currentPageKey, three, "after a relaunch")
    }

    /// 🎧 plays a page, and opening it again refreshes its text while the older text plays on.
    /// Saving the refreshed article gives the page no playhead from the session (it plays the
    /// older text), and nothing that session reaches is written there.
    func testSavingRefreshedTextWhileOlderTextPlaysGivesThePageNoPlayheadFromIt() throws {
        speech.listen(to: env.article(url, paragraphs: firstText))
        let heard = listen(to: 2)
        let key = ArticleIdentity.articleKey(url: URL(string: url)!)
        let page = try XCTUnwrap(library.page(key: key))
        XCTAssertEqual(spot(page), heard)
        let refreshed = open(secondText)
        listen(to: 3)

        try ArticleSaveCoordinator(library: library, speech: speech).save(refreshed)
        XCTAssertTrue(page.isSavedToLibrary)
        XCTAssertEqual(page.positionParagraph, heard.paragraph, "no playhead from the older text")
        XCTAssertEqual(speech.activeSessionID, key, "playback goes on")

        try relaunch()
        XCTAssertEqual(env.library.page(key: key)?.positionParagraph, heard.paragraph, "after a relaunch")
    }

    // MARK: - Rollbacks

    /// Opening a page refreshes its text and stores it while an older session plays on; opening
    /// it again brings the first text back, but saves fail now, so the store still holds the
    /// second. The session plays the first text again, as the page does for now, and what it
    /// reaches is written. A failed edit's rollback puts the stored (second) text back: that
    /// position, made in the first, isn't written again on it. A relaunch agrees.
    func testARollbackWritesProgressAgainOnlyOnTheTextItWasMadeIn() throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        play(page)
        let heard = listen(to: 1)
        open(secondText)
        XCTAssertFalse(env.context.hasChanges, "the refresh is stored")
        listen(to: 2)
        XCTAssertEqual(spot(page), heard, "the stored page holds other text: nothing written")

        failSaves()
        open(firstText)
        XCTAssertEqual(page.cachedListenParagraphs, firstText, "the first text is back, not stored")
        let unstored = listen(to: 3)
        XCTAssertEqual(spot(page), unstored, "the page holds the text playing: written")

        XCTAssertThrowsError(try library.makeFolder(name: "Shelf", in: nil), "an edit that fails")
        XCTAssertEqual(page.cachedListenParagraphs, secondText, "rolled back to the stored text")
        XCTAssertEqual(spot(page), heard, "the position in the first text isn't written on the second")

        allowSaves()
        library.commit("saves work")
        try relaunch()
        let reopened = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(reopened.cachedListenParagraphs, secondText, "after a relaunch")
        XCTAssertEqual(spot(reopened), heard, "after a relaunch")
    }

    /// While saves fail, a page plays to paragraph 2, stops, is refreshed on open, and is played
    /// again from the refreshed article, from its top. That play is the new text's listening, and
    /// starts the page's listening not stored yet over: a failed edit's rollback writes the
    /// refreshed text again with that start and spot, and the position reached in the older text
    /// isn't carried onto it. A relaunch agrees.
    func testAPlayOfRefreshedTextStartsItsListeningOverThroughARollback() throws {
        let page = try library.save(env.article(url, paragraphs: firstText))
        let key = page.listenKey
        let stored = spot(page)
        play(page)
        failSaves()
        listen(to: 2)
        speech.stop()
        env.now += 60

        let refreshed = open(secondText)
        speech.listen(to: refreshed)
        XCTAssertEqual(speech.document.paragraphs, secondText, "the refreshed text plays")
        let startedAt = try XCTUnwrap(page.lastPlayedAt)
        XCTAssertEqual(startedAt, env.now)

        XCTAssertThrowsError(try library.makeFolder(name: "Shelf", in: nil), "an edit that fails")
        XCTAssertEqual(page.cachedListenParagraphs, secondText, "the play's text is written again")
        XCTAssertEqual(page.lastPlayedAt, startedAt, "with its start")
        XCTAssertEqual(spot(page), stored, "from its top, not where the older text had got to")

        allowSaves()
        library.commit("saves work")
        try relaunch()
        let reopened = try XCTUnwrap(env.library.page(key: key))
        XCTAssertEqual(reopened.cachedListenParagraphs, secondText, "after a relaunch")
        XCTAssertEqual(reopened.lastPlayedAt, startedAt, "after a relaunch")
        XCTAssertEqual(spot(reopened), stored, "after a relaunch")
    }

    // MARK: - Recording as always

    /// Save lands on an older page holding the address under another key: the session playing
    /// the article (the same text) moves onto the page's key without stopping, and what it
    /// reaches is written there. A relaunch agrees.
    func testSavingOntoAnOlderKeyMovesThePlayingSessionAndItsListening() throws {
        let olderKey = UUID()
        let older = library.recordPlayback(env.article(url, paragraphs: firstText, key: olderKey))
        let article = env.article(url, paragraphs: firstText)
        XCTAssertNotEqual(article.id, olderKey)
        speech.listen(to: article)

        XCTAssertEqual(try ArticleSaveCoordinator(library: library, speech: speech).save(article), olderKey)
        XCTAssertEqual(speech.activeSessionID, olderKey, "the session moved onto the page's key")
        XCTAssertEqual(speech.playbackPhase, .playing, "without stopping")
        let heard = listen(to: 2)
        XCTAssertEqual(spot(older), heard, "and is recorded there")

        try relaunch()
        let reopened = try XCTUnwrap(env.library.page(key: olderKey))
        XCTAssertTrue(reopened.isSavedToLibrary)
        XCTAssertEqual(spot(reopened), heard, "after a relaunch")
    }

    /// A page saved before the library (a v1 save: its random key kept, its listen blocks copied)
    /// is found by its address. 🎧 plays it under that key, adopting the audio a v1 cache key
    /// holds, and what it reaches is written on it. A relaunch agrees.
    func testALegacyPageAdoptedByItsAddressRecordsItsListening() async throws {
        let extracted = DelayedExtractor.article(title: "Legacy")
        let legacyKey = UUID()
        env.legacyRow(url, id: legacyKey, title: "Legacy", savedAt: env.now,
                      paragraphs: ParagraphDocument.forListening(plainText: extracted.plainText,
                                                                 cleanedHTML: extracted.cleanedHTML).paragraphs)
        library.migrateLegacy()
        let v1 = try XCTUnwrap(ReaderArticle(id: legacyKey, url: URL(string: url)!, extracted: extracted).legacyCacheKeys.first)
        try storeTone(in: speech.localTTS, key: v1, text: "The v1 render.")

        let outcome = await PageArticleService.listen(toPageAt: URL(string: url)!, speech: speech, library: library) {
            library.readerArticle(url: URL(string: url)!, extracted: extracted)
        }
        guard case .started(let article) = outcome else { return XCTFail("🎧 didn't start: \(outcome)") }
        XCTAssertEqual(article.id, legacyKey, "the page's own key")
        XCTAssertTrue(speech.localTTS.audioCache.hasCache(for: legacyKey), "the v1 audio is adopted into it")
        let heard = listen(to: 2)
        speech.pause()
        XCTAssertEqual(spot(library.page(key: legacyKey)), heard)

        try relaunch()
        XCTAssertEqual(spot(env.library.page(key: legacyKey)), heard, "after a relaunch")
        XCTAssertNotNil(env.library.page(key: legacyKey)?.lastPlayedAt)
    }

    /// A rendered paragraph under `key` in `tts`'s audio cache.
    private func storeTone(in tts: LocalTTSCoordinator, key: UUID, text: String) throws {
        let tone = env.dir.appending(path: "tone-\(UUID().uuidString).caf")
        try LocalPCMWriter.write([Float](repeating: 0.1, count: 2400), sampleRate: 24_000, to: tone)
        try tts.audioCache.storeParagraph(articleID: key, paragraphIndex: 0, sourceURL: tone, duration: 0.1,
                                          engineID: tts.cacheEngineID, voiceID: "voiceA", text: text)
    }
}
