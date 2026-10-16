import SwiftData
import UIKit
import XCTest
@testable import MeridianReader

/// An imported book's *Replace* under the library's save rules: it is one edit
/// (`LibraryStore.edit`), so stopping the chapter it changes never stores half of it, and the
/// listening that stop records outlives a Replace that fails. A dropped or merged chapter's audio
/// work acts on the page holding its key when it runs, as every audio record does, and a session
/// a waiting merge would move stops when a Replace or delete changes the chapter it would move to.
@MainActor
final class BookSaveFailureTests: XCTestCase {
    private var fixture: TestSpeech!
    private var env: LibraryTestEnvironment!
    private var recorder: ListeningProgressRecorder?
    private let notifications = NotificationCenter()
    private var speech: SpeechController { fixture.speech }
    private var library: LibraryStore { env.library }

    private let bookKey = UUID()
    private let one = UUID(), two = UUID(), three = UUID(), four = UUID()
    private let textOne = ["One begins.", "One goes on.", "One ends."]
    private let textTwo = ["Two begins.", "Two goes on.", "Two ends."]
    private let textThree = ["Three begins.", "Three goes on.", "Three ends."]
    private let editedTwo = ["Two begins.", "Two goes on, differently now.", "Two ends."]

    override func setUp() async throws {
        fixture = TestSpeech()
        env = try LibraryTestEnvironment(fileBacked: true)
        recorder = ListeningProgressRecorder(speech: fixture.speech, library: env.library,
                                             notificationCenter: notifications)
    }

    override func tearDown() async throws {
        recorder = nil
        fixture.tearDown()
        env.cleanUp()
    }

    private struct SaveFailed: Error {}
    private func failSaves() { library.saveContext = { _ in throw SaveFailed() } }
    private func allowSaves() { library.saveContext = { try $0.save() } }

    // MARK: - Helpers

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

    private func addBook() throws -> Folder {
        try library.addBook(details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                chapter(three, 2, "Three", textThree)], in: nil)
    }

    /// Chapter one as it was, chapter two edited, chapter three dropped, chapter four new.
    private var replacement: [PageContent] {
        [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo), chapter(four, 2, "Four", ["Four is new."])]
    }

    /// A row's ▶ on `page`, as `LibraryActions.play` does it.
    private func play(_ page: Page) {
        speech.press(.page(page.listenKey)) {
            speech.start(.page(page), at: page.listenStart)
        }
    }

    /// Replace stops the chapter it changes as the app does (`AppComposition.makeLibrary`), and
    /// stopping records the spot inside the paragraph.
    private func stopsPlaybackOnReplace(then afterStop: @escaping () -> Void = {}) {
        library.stopPlaybackIfPlaying = { [unowned self] key in
            guard speech.activeSessionID == key else { return }
            speech.stop()
            afterStop()
        }
    }

    private func audioWork(in context: ModelContext) -> [LibraryAudioWork] {
        (try? context.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
    }

    /// Every file under a key's audio directory in the library's cache, by relative path.
    private func audioFiles(_ key: UUID) throws -> [String: Data] {
        let dir = env.cache.directory(for: key)
        var out: [String: Data] = [:]
        for name in FileManager.default.subpaths(atPath: dir.path) ?? [] {
            var isDir: ObjCBool = false
            let url = dir.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out[name] = try Data(contentsOf: url)
        }
        return out
    }

    private func assertBookAsItWas(_ library: LibraryStore, spot: (paragraph: Int, utf16: Int), audio: [[String: Data]],
                                   _ when: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let book = try XCTUnwrap(library.book(key: bookKey), when, file: file, line: line)
        XCTAssertEqual(library.playOrder(of: book).map(\.key), [one, two, three],
                       "\(when): no chapter dropped or added", file: file, line: line)
        XCTAssertEqual(library.page(key: two)?.cachedListenParagraphs, textTwo, "\(when): no text changed", file: file, line: line)
        XCTAssertEqual(library.page(key: two)?.positionParagraph, spot.paragraph, "\(when): the spot stopping recorded",
                       file: file, line: line)
        XCTAssertEqual(library.page(key: two)?.positionUTF16, spot.utf16, "\(when): inside its paragraph", file: file, line: line)
        XCTAssertEqual(try [two, three].map { try audioFiles($0) }, audio, "\(when): no audio aligned or deleted",
                       file: file, line: line)
        XCTAssertTrue(audioWork(in: library.context).isEmpty, "\(when): no audio work waits", file: file, line: line)
    }

    // MARK: - Replace and the chapter it stops

    /// Replace edits the playing chapter and drops another. Stopping that playback records its
    /// spot, and that save works; Replace's own save then fails. Nothing of the Replace is stored,
    /// in the store or on disk: no position save carries it half made. The stopped chapter keeps
    /// its spot, stored once saves work, and a relaunch agrees.
    func testAReplaceThatFailsReplacesNothingThoughStoppingItsPlayingChapterRecordsASpot() throws {
        _ = try addBook()
        for (key, text) in [(two, textTwo), (three, textThree)] { try env.storeAudio(key, paragraphs: text) }
        let audioBefore = try [two, three].map { try audioFiles($0) }
        play(try XCTUnwrap(library.page(key: two)))
        let p1 = speech.document.startUTF16Offset(forParagraph: 1)
        fixture.apple.emit(.position(paragraph: 1, utf16: p1))
        fixture.apple.emit(.position(paragraph: 1, utf16: p1 + 5))
        var failing = false
        library.saveContext = { if failing { throw SaveFailed() }; try $0.save() }
        stopsPlaybackOnReplace { failing = true }

        let book = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertThrowsError(try library.replaceBook(book, with: details, chapters: replacement)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertNil(speech.nowPlaying, "playback of the edited chapter stopped")
        XCTAssertFalse(env.context.hasChanges, "nothing waits for a later save")
        try assertBookAsItWas(library, spot: (1, p1 + 5), audio: audioBefore, "after the failed Replace")

        allowSaves()
        library.commit("next")
        recorder = nil
        try env.relaunch()
        try assertBookAsItWas(env.library, spot: (1, p1 + 5), audio: audioBefore, "after a relaunch")
    }

    /// Saves fail from before the Replace: the spot stopping records can't be saved either. The
    /// Replace's rollback writes it again on the chapter as it was, and it is stored once saves
    /// work.
    func testAReplaceWhileSavesFailKeepsTheStoppedChapterAtItsSpot() throws {
        _ = try addBook()
        for (key, text) in [(two, textTwo), (three, textThree)] { try env.storeAudio(key, paragraphs: text) }
        let audioBefore = try [two, three].map { try audioFiles($0) }
        play(try XCTUnwrap(library.page(key: two)))
        let p2 = speech.document.startUTF16Offset(forParagraph: 2)
        fixture.apple.emit(.position(paragraph: 2, utf16: p2))
        fixture.apple.emit(.position(paragraph: 2, utf16: p2 + 3))
        stopsPlaybackOnReplace()
        failSaves()

        let book = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertThrowsError(try library.replaceBook(book, with: details, chapters: replacement)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertNil(speech.nowPlaying, "playback stopped")
        try assertBookAsItWas(library, spot: (2, p2 + 3), audio: audioBefore, "after the failed Replace")

        allowSaves()
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        recorder = nil
        try env.relaunch()
        try assertBookAsItWas(env.library, spot: (2, p2 + 3), audio: audioBefore, "stored once saves work, after a relaunch")
    }

    // MARK: - A dropped chapter's audio work

    /// A Replace edits chapter three, and aligning its audio fails, so that work waits; a second
    /// drops the chapter, and deleting its audio waits behind the align. A third brings the
    /// chapter back. When the next launch runs the waiting work, the delete finds a chapter saved
    /// in the Library holding the key: it keeps the audio and marks it saved, as that page is,
    /// rather than deleting it or leaving it ephemeral.
    func testAWaitingDeleteOfADroppedChapterSettlesItsAudioByThePageAsItIsNow() throws {
        let book = try addBook()
        try env.storeAudio(three, paragraphs: textThree)
        env.cache.markEphemeral(cacheKey: three)
        let editedThree = ["Three begins.", "Three goes on, otherwise.", "Three ends."]
        let withThree = [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo), chapter(three, 2, "Three", editedThree)]

        env.cache.faultHook = { _ in throw SaveFailed() }
        try library.replaceBook(book, with: details, chapters: withThree)
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo)])
        XCTAssertNil(library.page(key: three), "the drop is saved")
        try library.replaceBook(book, with: details, chapters: withThree)
        XCTAssertNotNil(library.page(key: three), "the chapter is back")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .delete], "the delete waits behind the align")
        XCTAssertTrue(env.cache.hasDirectory(for: three), "nothing deleted yet")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .ephemeral)

        recorder = nil
        try env.relaunch()
        XCTAssertEqual(env.library.finishAudioWork().finished, 2, "next launch: the align, then the delete")
        XCTAssertTrue(audioWork(in: env.context).isEmpty, "both retired")
        XCTAssertEqual(env.cache.readyIndices(articleID: three, paragraphCount: 3, engineID: env.tts.cacheEngineID, voiceID: "voiceA"),
                       [0, 2], "the chapter that came back keeps its audio, aligned to its text")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .saved, "saved, as the chapter is")
    }

    // MARK: - A merged chapter's audio work

    /// The chapter text that comes back under key `three` in place of `textThree`.
    private let textNew = ["A new third chapter opens.", "It takes its own way.", "And it closes."]
    /// Chapter three's text moves here (`renamed`), then the new text moves on to `five`.
    private let renamed = UUID(), five = UUID()

    private var withRenamed: [PageContent] {
        [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo), chapter(renamed, 2, "Three", textThree)]
    }

    /// A Replace edits chapter two and finds chapter three's text under `renamed`, with chapter
    /// three at a spot and the crash-resume point on it. Aligning two's audio fails, so that work
    /// and the merge after it wait. Every audio step fails until the caller lets them through
    /// (`env.cache.faultHook = nil`).
    private func mergeThreeIntoRenamedThatWaits() throws -> (book: Folder, spot: (paragraph: Int, utf16: Int)) {
        let book = try addBook()
        try env.storeAudio(two, paragraphs: textTwo)
        try env.storeAudio(three, paragraphs: textThree)
        let spot = (paragraph: 1, utf16: ParagraphDocument(parts: textThree).utf16Ranges[1].location + 4)
        library.recordPosition(try XCTUnwrap(library.page(key: three)), paragraph: spot.paragraph, utf16Offset: spot.utf16)
        ListenResumePointStore.shared.save(article: three, paragraph: spot.paragraph, at: env.now)
        env.cache.faultHook = { _ in throw SaveFailed() }
        try library.replaceBook(book, with: details, chapters: withRenamed)
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge], "the merge waits behind the align")
        XCTAssertEqual(library.page(key: renamed)?.positionParagraph, spot.paragraph, "the spot is carried")
        XCTAssertTrue(env.cache.hasDirectory(for: three), "nothing moved yet")
        return (book, spot)
    }

    /// Merges reach the live session as the app wires them (`AppComposition.makeLibrary`);
    /// returns the merges reported so far.
    private func sessionFollowsMerges() -> () -> [[UUID]] {
        var merged: [[UUID]] = []
        library.keyMerged = { [unowned self] from, to, text in
            merged.append([from, to])
            speech.rekeyActiveSession(from: from, to: to, text: text)
        }
        return { merged }
    }

    /// Chapter three's new text, rendered under its key (each paragraph's audio its own bytes),
    /// with a pending render waiting for the engine.
    private func renderNewThree() throws {
        for (i, text) in textNew.enumerated() { try env.storeAudio(three, paragraph: i, text: text, level: 0.4 + Float(i) / 10) }
        PendingBakeJobStore.shared.enqueuePending(articleID: three, paragraphs: textNew, priorityStart: 0)
        addTeardownBlock { @MainActor in
            for key in [self.three, self.renamed, self.five] { PendingBakeJobStore.shared.removePending(articleID: key) }
        }
    }

    /// The audio files under `key` other than the cache's meta file, which marking saved rewrites.
    private func renders(_ key: UUID) throws -> [String: Data] {
        try audioFiles(key).filter { $0.key != "meta.json" }
    }

    private func bytes(_ key: UUID, paragraph: Int) throws -> Data? {
        guard let entry = env.cache.entry(articleID: key, paragraphIndex: paragraph) else { return nil }
        return try Data(contentsOf: env.cache.directory(for: key).appending(path: entry.file))
    }

    private func pendingRender(_ key: UUID) -> Bool {
        PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == key }
    }

    /// Plays chapter three (its new text) to `paragraph`; returns the spot.
    private func playNewThree(to paragraph: Int) throws -> (paragraph: Int, utf16: Int) {
        play(try XCTUnwrap(library.page(key: three)))
        XCTAssertEqual(speech.activeSessionID, three)
        return listen(to: paragraph)
    }

    /// Playback reaches `paragraph`; returns the spot that records.
    private func listen(to paragraph: Int) -> (paragraph: Int, utf16: Int) {
        let start = speech.document.startUTF16Offset(forParagraph: paragraph)
        fixture.apple.emit(.position(paragraph: paragraph, utf16: start))
        return (paragraph, start)
    }

    private func assertSpot(_ library: LibraryStore, _ key: UUID, _ spot: (paragraph: Int, utf16: Int), _ note: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(library.page(key: key)?.positionParagraph, spot.paragraph, note, file: file, line: line)
        XCTAssertEqual(library.page(key: key)?.positionUTF16, spot.utf16, note, file: file, line: line)
    }

    /// Replace finds chapter three's text under `renamed`, and the merge waits. A second Replace
    /// keeps `renamed` and brings key three back with new text, which is rendered and played.
    /// Saving an unrelated article then runs the waiting merge. Key three is the new chapter's
    /// now: its audio, its pending render, its session and the crash-resume point on it stay
    /// three's, nothing moves under `renamed`, no session is rekeyed, and listening goes on being
    /// recorded on three, while `renamed` keeps the spot it was given. A relaunch agrees.
    func testAWaitingMergeLeavesAChapterBackUnderItsKeyAndItsSessionAlone() throws {
        let (book, carried) = try mergeThreeIntoRenamedThatWaits()
        let merged = sessionFollowsMerges()
        stopsPlaybackOnReplace()
        try library.replaceBook(book, with: details, chapters: withRenamed + [chapter(three, 3, "Three again", textNew)])
        XCTAssertEqual(library.page(key: three)?.cachedListenParagraphs, textNew, "key three is back, with new text")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge], "the merge still waits")
        env.cache.faultHook = nil
        try renderNewThree()
        let audio = try renders(three)
        _ = try playNewThree(to: 1)

        _ = try library.save(env.article("https://example.com/elsewhere"))
        XCTAssertTrue(audioWork(in: env.context).isEmpty, "the waiting merge ran with the article's audio work, and is retired")
        XCTAssertTrue(merged().isEmpty, "no session is rekeyed")
        XCTAssertEqual(speech.activeSessionID, three, "the session is still chapter three's")
        XCTAssertEqual(try renders(three), audio, "chapter three keeps its audio")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .saved, "saved, as the chapter is")
        XCTAssertTrue(pendingRender(three), "and its pending render")
        XCTAssertEqual(ListenResumePointStore.shared.load()?.articleKey, three.uuidString, "and the crash-resume point")
        XCTAssertFalse(env.cache.hasDirectory(for: renamed), "nothing moved under the merge's key")

        let spot = listen(to: 2)
        assertSpot(library, three, spot, "listening is recorded on chapter three")
        assertSpot(library, renamed, carried, "the merged chapter keeps its own spot")

        recorder = nil
        try env.relaunch()
        assertSpot(env.library, three, spot, "after a relaunch")
        assertSpot(env.library, renamed, carried, "after a relaunch")
        XCTAssertEqual(try renders(three), audio, "after a relaunch")
        XCTAssertFalse(env.cache.hasDirectory(for: renamed), "after a relaunch")
        XCTAssertTrue(pendingRender(three), "after a relaunch")
        XCTAssertTrue(audioWork(in: env.context).isEmpty)
    }

    /// As above, but the second Replace also drops `renamed`, so the waiting merge finds no page
    /// to merge into. Key three is the new chapter's: its audio is kept, marked saved as the
    /// chapter is (not left to the age prune as audio no page holds), its pending render stays,
    /// and its session and listening stay three's. A relaunch agrees.
    func testAWaitingMergeWithNoKeptPageLeavesAChapterBackUnderItsKeySaved() throws {
        let (book, _) = try mergeThreeIntoRenamedThatWaits()
        let merged = sessionFollowsMerges()
        stopsPlaybackOnReplace()
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo),
                                                                chapter(three, 2, "Three again", textNew)])
        XCTAssertNil(library.page(key: renamed), "the kept page is dropped")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge, .delete], "all wait behind the align")
        env.cache.faultHook = nil
        try renderNewThree()
        // The record has to settle the audio: it starts on the ephemeral TTL.
        env.cache.markEphemeral(cacheKey: three)
        let audio = try renders(three)
        _ = try playNewThree(to: 1)

        _ = try library.save(env.article("https://example.com/elsewhere"))
        XCTAssertTrue(audioWork(in: env.context).isEmpty, "the align, the merge and the delete ran and are retired")
        XCTAssertTrue(merged().isEmpty, "no session is rekeyed")
        XCTAssertEqual(speech.activeSessionID, three)
        XCTAssertEqual(try renders(three), audio, "chapter three keeps its audio")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .saved, "saved, as the chapter is")
        XCTAssertTrue(pendingRender(three), "and its pending render")
        XCTAssertFalse(env.cache.hasDirectory(for: renamed))

        let spot = listen(to: 2)
        assertSpot(library, three, spot, "listening is recorded on chapter three")

        recorder = nil
        try env.relaunch()
        assertSpot(env.library, three, spot, "after a relaunch")
        XCTAssertNil(env.library.page(key: renamed))
        XCTAssertEqual(try renders(three), audio, "after a relaunch")
        XCTAssertEqual(env.cache.loadMeta(for: three)?.kind, .saved, "after a relaunch")
        XCTAssertTrue(pendingRender(three), "after a relaunch")
        XCTAssertTrue(audioWork(in: env.context).isEmpty)
    }

    /// Key three comes back with new text while the merge into `renamed` waits, and is played;
    /// a third Replace finds that text under `five`, so it merges again, and the playing session
    /// follows. Both merges run in the third Replace's save. The first finds that a later record
    /// names key three (the chapter that had it since): it leaves the key to that record, which
    /// moves the new text's audio and session to `five`. Nothing goes to `renamed`, and
    /// listening is recorded on `five`. A relaunch agrees.
    func testAWaitingMergeLeavesAKeyThatCameBackAndMergedAgainToTheLaterMerge() throws {
        let (book, carried) = try mergeThreeIntoRenamedThatWaits()
        let merged = sessionFollowsMerges()
        stopsPlaybackOnReplace()
        try library.replaceBook(book, with: details, chapters: withRenamed + [chapter(three, 3, "Three again", textNew)])
        env.cache.faultHook = nil
        try renderNewThree()
        let audio = try (0..<textNew.count).map { try XCTUnwrap(bytes(three, paragraph: $0)) }
        _ = try playNewThree(to: 1)

        try library.replaceBook(book, with: details, chapters: withRenamed + [chapter(five, 3, "Three again", textNew)])
        XCTAssertTrue(audioWork(in: env.context).isEmpty, "both merges ran in the Replace's save, and are retired")
        XCTAssertEqual(merged(), [[three, five]], "only the later merge moves the session")
        XCTAssertEqual(speech.activeSessionID, five, "the session follows the new text")
        XCTAssertEqual(try (0..<textNew.count).map { try bytes(five, paragraph: $0) }, audio, "its audio too")
        XCTAssertFalse(env.cache.hasDirectory(for: three))
        XCTAssertFalse(env.cache.hasDirectory(for: renamed), "none of it went to the first merge's page")

        let spot = listen(to: 2)
        assertSpot(library, five, spot, "listening is recorded on the new text's chapter")
        assertSpot(library, renamed, carried, "the first merge's page keeps its own spot")

        recorder = nil
        try env.relaunch()
        assertSpot(env.library, five, spot, "after a relaunch")
        assertSpot(env.library, renamed, carried, "after a relaunch")
        XCTAssertEqual(try (0..<textNew.count).map { try bytes(five, paragraph: $0) }, audio, "after a relaunch")
        XCTAssertFalse(env.cache.hasDirectory(for: renamed), "after a relaunch")
        XCTAssertTrue(audioWork(in: env.context).isEmpty)
    }

    // MARK: - A session a waiting merge would move

    /// Chapter three as `renamed` revises it: its first paragraph is longer, so the second,
    /// unchanged, starts elsewhere; its last is changed.
    private let revisedThree = ["Three begins, now at more length.", "Three goes on.", "Three ends, revised."]

    private func withRevisedRenamed(_ more: [PageContent] = []) -> [PageContent] {
        [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo), chapter(renamed, 2, "Three", revisedThree)] + more
    }

    /// Chapter three plays to its second paragraph; a Replace edits chapter two and finds three's
    /// text under `renamed`, carrying the spot there. Aligning two's audio fails, so the merge that
    /// would move the session onto `renamed` waits, and the session plays on under key three.
    /// Every audio step fails until the caller lets them through.
    private func playThreeWhileItsMergeWaits() throws
        -> (book: Folder, carried: (paragraph: Int, utf16: Int), merged: () -> [[UUID]]) {
        let book = try addBook()
        try env.storeAudio(two, paragraphs: textTwo)
        try env.storeAudio(three, paragraphs: textThree)
        let merged = sessionFollowsMerges()
        stopsPlaybackOnReplace()
        play(try XCTUnwrap(library.page(key: three)))
        let spot = listen(to: 1)
        env.cache.faultHook = { _ in throw SaveFailed() }
        try library.replaceBook(book, with: details, chapters: withRenamed)
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge], "the merge waits behind the align")
        XCTAssertEqual(speech.activeSessionID, three, "the session plays on under the merged key")
        XCTAssertNotNil(speech.nowPlaying)
        assertSpot(library, renamed, spot, "the spot is carried")
        return (book, spot, merged)
    }

    /// Lets the waiting work through and runs it with an unrelated save; then the engine reports
    /// the next paragraph of chapter three's old text, as it would if that session still played.
    private func runWaitingWorkThenHearTheOldText() throws {
        env.cache.faultHook = nil
        _ = try library.save(env.article("https://example.com/elsewhere"))
        XCTAssertTrue(audioWork(in: env.context).isEmpty, "the waiting work ran and is retired")
        fixture.apple.emit(.position(paragraph: 2, utf16: ParagraphDocument(parts: textThree).utf16Ranges[2].location))
    }

    /// Chapter three plays while its merge into `renamed` waits, and a second Replace revises
    /// `renamed`. The session stops with that Replace, as playback of the revised chapter does:
    /// the merge, which follows what `renamed` holds when it runs, would otherwise move it onto
    /// the revised text and record positions in the old text there. No page holds key three, so
    /// the stop records nothing; `renamed` keeps the spot carried to it, carried on into the
    /// revision. The merge then runs with no live session to move, and nothing more is recorded.
    /// A relaunch agrees.
    func testAReplaceRevisingAKeptChapterStopsTheSessionAWaitingMergeWouldMoveOntoIt() throws {
        let (book, carried, merged) = try playThreeWhileItsMergeWaits()
        try library.replaceBook(book, with: details, chapters: withRevisedRenamed())
        XCTAssertNil(speech.nowPlaying, "the session stopped with the Replace")
        XCTAssertNil(speech.activeSessionID)
        XCTAssertEqual(library.page(key: renamed)?.cachedListenParagraphs, revisedThree)
        let revised = (paragraph: 1, utf16: ParagraphDocument(parts: revisedThree).utf16Ranges[1].location)
        XCTAssertNotEqual(revised.utf16, carried.utf16, "the unchanged paragraph starts elsewhere in the revision")
        assertSpot(library, renamed, revised, "the carried spot, carried on into the revision")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge, .align], "the merge still waits")

        try runWaitingWorkThenHearTheOldText()
        XCTAssertEqual(merged(), [[three, renamed]], "the merge ran")
        XCTAssertFalse(env.cache.hasDirectory(for: three), "and took chapter three's audio")
        XCTAssertNil(speech.activeSessionID, "with no live session to move")
        assertSpot(library, renamed, revised, "no position in the old text is recorded on the revised chapter")

        recorder = nil
        try env.relaunch()
        assertSpot(env.library, renamed, revised, "after a relaunch")
        XCTAssertTrue(audioWork(in: env.context).isEmpty)
    }

    /// As above, but the second Replace drops `renamed`. The session stops with it: the merge
    /// would find no page to move it onto and leave it playing a key no page holds. When the
    /// work runs, nothing is moved and nothing recorded. A relaunch agrees.
    func testAReplaceDroppingAKeptChapterStopsTheSessionAWaitingMergeWouldMoveOntoIt() throws {
        let (book, _, merged) = try playThreeWhileItsMergeWaits()
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedTwo)])
        XCTAssertNil(speech.nowPlaying, "the session stopped with the Replace")
        XCTAssertNil(library.page(key: renamed), "the kept chapter is dropped")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge, .delete], "all wait behind the align")

        try runWaitingWorkThenHearTheOldText()
        XCTAssertTrue(merged().isEmpty, "the merge found no page to move anything onto")
        XCTAssertNil(speech.activeSessionID)
        XCTAssertNil(library.page(key: three), "no page is made for the stopped session")

        recorder = nil
        try env.relaunch()
        XCTAssertEqual(env.library.playOrder(of: try XCTUnwrap(env.library.book(key: bookKey))).map(\.key), [one, two])
        XCTAssertNil(env.library.page(key: three))
        XCTAssertTrue(audioWork(in: env.context).isEmpty)
    }

    /// While chapter three's merge into `renamed` waits, `renamed` is deleted (a row's *Delete*).
    /// The session on key three stops with the delete, even one whose save fails: that chapter
    /// then stays, at the spot carried to it, and nothing of the stopped session is recorded on
    /// it. Once a delete is saved and the work runs, no session is moved. A relaunch agrees.
    func testDeletingAKeptChapterStopsTheSessionAWaitingMergeWouldMoveOntoIt() throws {
        let (_, carried, merged) = try playThreeWhileItsMergeWaits()
        failSaves()
        library.delete(try XCTUnwrap(library.page(key: renamed)))
        XCTAssertNil(speech.nowPlaying, "the session stopped with the delete")
        assertSpot(library, renamed, carried, "the delete's save failed: the chapter stays, at the spot carried to it")
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge], "only the merge waits")

        allowSaves()
        library.delete(try XCTUnwrap(library.page(key: renamed)))
        XCTAssertNil(library.page(key: renamed))
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge, .delete])
        try runWaitingWorkThenHearTheOldText()
        XCTAssertTrue(merged().isEmpty, "the merge found no page to move anything onto")
        XCTAssertNil(speech.activeSessionID)
        XCTAssertNil(library.page(key: three), "no page is made for the stopped session")

        recorder = nil
        try env.relaunch()
        XCTAssertEqual(env.library.playOrder(of: try XCTUnwrap(env.library.book(key: bookKey))).map(\.key), [one, two])
        XCTAssertTrue(audioWork(in: env.context).isEmpty)
    }

    /// The merge into `renamed` waits; a Replace brings key three back with new text, which is
    /// played. A Replace revising `renamed` leaves that session alone: it is the returned
    /// chapter's, which the waiting merge doesn't move.
    func testAReplaceRevisingAKeptChapterLeavesAChapterBackUnderTheMergedKeyPlaying() throws {
        let (book, _) = try mergeThreeIntoRenamedThatWaits()
        stopsPlaybackOnReplace()
        try library.replaceBook(book, with: details, chapters: withRenamed + [chapter(three, 3, "Three again", textNew)])
        _ = try playNewThree(to: 1)
        try library.replaceBook(book, with: details, chapters: withRevisedRenamed([chapter(three, 3, "Three again", textNew)]))
        XCTAssertEqual(speech.activeSessionID, three, "the chapter back under key three plays on")
        XCTAssertNotNil(speech.nowPlaying)
    }

    /// Key three comes back with new text and is played, and a later Replace finds that text under
    /// `five`: a second merge of key three waits after the first. A Replace revising `renamed`
    /// leaves the session alone, since the later merge, into `five`, is the one that moves it; it
    /// does once the work runs.
    func testAReplaceRevisingAKeptChapterLeavesASessionALaterMergeMovesElsewhere() throws {
        let (book, _) = try mergeThreeIntoRenamedThatWaits()
        let merged = sessionFollowsMerges()
        stopsPlaybackOnReplace()
        try library.replaceBook(book, with: details, chapters: withRenamed + [chapter(three, 3, "Three again", textNew)])
        _ = try playNewThree(to: 1)
        try library.replaceBook(book, with: details, chapters: withRenamed + [chapter(five, 3, "Three again", textNew)])
        XCTAssertEqual(audioWork(in: env.context).map(\.kind), [.align, .merge, .merge], "both merges wait")
        try library.replaceBook(book, with: details, chapters: withRevisedRenamed([chapter(five, 3, "Three again", textNew)]))
        XCTAssertEqual(speech.activeSessionID, three, "the session plays on, for the later merge to move")
        XCTAssertNotNil(speech.nowPlaying)

        env.cache.faultHook = nil
        _ = try library.save(env.article("https://example.com/elsewhere"))
        XCTAssertEqual(merged(), [[three, five]], "only the later merge moves it")
        XCTAssertEqual(speech.activeSessionID, five)
    }
}
