import SwiftData
import XCTest
@testable import MeridianReader

/// *Replace* (decision D13): the book's pages rebuilt in the same folder. A chapter keeps what was
/// listened to only where its text shows it is the same chapter: a key match alone doesn't carry
/// a position into edited text.
@MainActor
final class BookReimportTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }
    private let bookKey = UUID()
    private var merged: [(UUID, UUID)] = []

    override func setUp() async throws {
        env = try LibraryTestEnvironment()
        library.keyMerged = { [unowned self] from, to, _ in merged.append((from, to)) }
    }

    override func tearDown() async throws { env.cleanUp() }

    private var details: FolderDetails {
        FolderDetails(kind: .book, title: "The Book", byline: "Ada Example", cover: nil, sourceURL: nil,
                      sourceIdentifier: bookKey.uuidString, languageCode: "en", sourceState: nil)
    }

    private func chapter(_ key: UUID, _ ordinal: Int, _ title: String, _ paragraphs: [String],
                         skips: Bool = false) -> PageContent {
        let ref = PageRef(key: key, locator: .book(EPUBLocator(href: "OEBPS/c\(ordinal).xhtml", anchor: .fileStart)),
                          ordinal: ordinal, title: title, skipsInPlayback: skips)
        return PageContent(ref: ref, title: title, bodyHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                           plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
    }

    private let one = UUID(), two = UUID(), three = UUID()
    private let textOne = ["One begins.", "One goes on.", "One ends."]
    private let textTwo = ["Two begins.", "Two goes on.", "Two ends."]
    private let textThree = ["Three begins.", "Three goes on.", "Three ends."]

    private func addBook() throws -> Folder {
        try library.addBook(details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                chapter(three, 2, "Three", textThree)], in: nil)
    }

    private func page(_ key: UUID) -> Page? { library.page(key: key) }

    private func ready(_ key: UUID, _ count: Int = 3) -> Set<Int> {
        env.cache.readyIndices(articleID: key, paragraphCount: count, engineID: env.tts.cacheEngineID, voiceID: "voiceA")
    }

    func testUnchangedChaptersKeepEverythingAndTheFolderKeepsItsPlaceAndName() throws {
        let book = try addBook()
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        try library.move([.folder(book)], to: shelf)
        try library.rename(book, to: "My Name For It")
        let p2 = try XCTUnwrap(page(two))
        library.recordPlayback(ReaderArticle(page: p2))
        library.recordPosition(p2, paragraph: 2, utf16Offset: 30)
        library.recordFinished(try XCTUnwrap(page(one)))
        try env.storeAudio(two, paragraphs: textTwo)

        var newDetails = details
        newDetails.byline = "Ada Example, Ben Sample"
        try library.replaceBook(book, with: newDetails, chapters: [chapter(one, 0, "One", textOne),
                                                                   chapter(two, 1, "Two", textTwo),
                                                                   chapter(three, 2, "Three", textThree)])
        XCTAssertTrue(book.parent === shelf, "its place in the tree")
        XCTAssertEqual(book.name, "My Name For It", "its name")
        XCTAssertEqual(book.byline, "Ada Example, Ben Sample", "its details are the file's")
        XCTAssertEqual(book.currentPageKey, two, "its place in the book")
        XCTAssertEqual(page(two)?.positionParagraph, 2)
        XCTAssertEqual(page(two)?.positionUTF16, 30)
        XCTAssertNotNil(page(one)?.finishedAt)
        XCTAssertEqual(page(two)?.byline, "Ada Example, Ben Sample")
        XCTAssertEqual(ready(two), [0, 1, 2], "its audio")
        XCTAssertEqual(env.pages().count, 3)
    }

    func testTheSameKeyWithEditedTextKeepsOnlyWhatTheTextStillShows() throws {
        let book = try addBook()
        let p2 = try XCTUnwrap(page(two))
        library.recordPosition(p2, paragraph: 2, utf16Offset: textTwo[0].utf16.count + textTwo[1].utf16.count + 4 + 3)
        try env.storeAudio(two, paragraphs: textTwo)
        env.playingKey = two

        let edited = ["Two begins.", "Two goes on, differently now.", "Two ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", edited),
                                                                chapter(three, 2, "Three", textThree)])
        let after = try XCTUnwrap(page(two))
        XCTAssertEqual(after.cachedListenParagraphs, edited)
        let start = ParagraphDocument(parts: edited).utf16Ranges[2].location
        XCTAssertEqual(after.positionParagraph, 2, "its paragraph is still there, word for word")
        XCTAssertEqual(after.positionUTF16, start + 3, "the same spot in it")
        XCTAssertEqual(ready(two), [0, 2], "audio kept only for the paragraphs that read the same")
        XCTAssertEqual(env.stoppedKeys, [two], "playback of the edited chapter stops")

        // Edited where the position is: it goes back to the chapter's start.
        library.recordPosition(after, paragraph: 1, utf16Offset: start - 5)
        let editedAgain = ["Two begins.", "Two goes on in a third way.", "Two ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", editedAgain),
                                                                chapter(three, 2, "Three", textThree)])
        XCTAssertEqual(page(two)?.positionParagraph, 0)
        XCTAssertEqual(page(two)?.positionUTF16, 0)
    }

    func testTheSameTextUnderANewKeyTakesOverPositionAudioAndPlace() throws {
        let book = try addBook()
        let p3 = try XCTUnwrap(page(three))
        library.recordPlayback(ReaderArticle(page: p3))
        library.recordPosition(p3, paragraph: 1, utf16Offset: 20)
        try env.storeAudio(three, paragraphs: textThree)
        let renamed = UUID()

        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                                chapter(renamed, 2, "Three", textThree)])
        XCTAssertNil(page(three), "the old key is gone")
        let moved = try XCTUnwrap(page(renamed))
        XCTAssertEqual(moved.positionParagraph, 1)
        XCTAssertEqual(moved.positionUTF16, 20)
        XCTAssertNotNil(moved.lastPlayedAt)
        XCTAssertEqual(book.currentPageKey, renamed, "the book's place follows it")
        XCTAssertEqual(ready(renamed), [0, 1, 2], "its audio moved under the new key")
        XCTAssertFalse(env.cache.hasDirectory(for: three))
        XCTAssertTrue(merged.contains { $0 == (three, renamed) }, "a session playing it follows")
    }

    func testChaptersNoLongerInTheBookGoWithTheirAudio() throws {
        let book = try addBook()
        try env.storeAudio(three, paragraphs: textThree)
        library.recordPlayback(ReaderArticle(page: try XCTUnwrap(page(three))))
        env.playingKey = three
        let four = UUID()

        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                                chapter(four, 2, "Four", ["Four is new."])])
        XCTAssertNil(page(three))
        XCTAssertFalse(env.cache.hasCache(for: three), "its audio is deleted")
        XCTAssertEqual(env.stoppedKeys, [three], "playback of it stops first")
        XCTAssertEqual(book.currentPageKey, two, "the place it held moves to the chapter before it")
        XCTAssertEqual(library.playOrder(of: book).map(\.key), [one, two, four])
    }

    /// As deleting a chapter does: a dropped place moves back to the nearest chapter that stays,
    /// under the key that chapter has now; to none when no chapter before it stays.
    func testADroppedPlaceMovesToTheNearestEarlierChapterThatStays() throws {
        let book = try addBook()
        library.recordPlayback(ReaderArticle(page: try XCTUnwrap(page(three))))
        let four = UUID()
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne),
                                                                chapter(four, 1, "Four", ["Four is new."])])
        XCTAssertEqual(book.currentPageKey, one, "two and three are both gone: back to one")

        library.recordPlayback(ReaderArticle(page: try XCTUnwrap(page(four))))
        let renamed = UUID()
        try library.replaceBook(book, with: details, chapters: [chapter(renamed, 0, "One", textOne)])
        XCTAssertEqual(book.currentPageKey, renamed, "one stays under a new key: the place takes it")

        let five = UUID()
        try library.replaceBook(book, with: details, chapters: [chapter(five, 0, "Five", ["Five is new."])])
        XCTAssertNil(book.currentPageKey, "the first chapter dropped, nothing before it")
    }

    // MARK: - A failed save, and audio work

    private struct Died: Error {}

    private func audioWork() -> [LibraryAudioWork] {
        (try? env.context.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))) ?? []
    }

    private func pendingRender(_ key: UUID) -> Bool {
        PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == key }
    }

    /// Checked on disk, after a relaunch: what the store holds, not only what the context shows.
    func testAFailedReplaceKeepsEveryPageAndItsAudio() throws {
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        let book = try addBook()
        try env.storeAudio(two, paragraphs: textTwo)
        try env.storeAudio(three, paragraphs: textThree)
        PendingBakeJobStore.shared.enqueuePending(articleID: three, paragraphs: textThree, priorityStart: 0)
        let dropped = three
        addTeardownBlock { @MainActor in PendingBakeJobStore.shared.removePending(articleID: dropped) }
        library.recordPlayback(ReaderArticle(page: try XCTUnwrap(page(three))))
        let four = UUID()
        let edited = ["Two begins.", "Two goes on, differently now.", "Two ends."]
        let replacement = [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", edited), chapter(four, 2, "Four", ["Four is new."])]

        library.saveContext = { _ in throw Died() }
        XCTAssertThrowsError(try library.replaceBook(book, with: details, chapters: replacement)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertEqual(ready(three), [0, 1, 2], "the dropped chapter's audio is still there")
        XCTAssertEqual(ready(two), [0, 1, 2], "and so is the edited one's")
        XCTAssertTrue(pendingRender(three), "and the dropped chapter's pending render")
        XCTAssertTrue(audioWork().isEmpty, "no work is left to run against a book that didn't change")

        try env.relaunch()
        let stored = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertEqual(library.playOrder(of: stored).map(\.key), [one, two, three], "every page is still there")
        XCTAssertEqual(page(two)?.cachedListenParagraphs, textTwo, "with its text")
        XCTAssertEqual(stored.currentPageKey, three, "and the book's place")
        XCTAssertEqual(ready(three), [0, 1, 2])
        XCTAssertEqual(ready(two), [0, 1, 2])
        XCTAssertTrue(audioWork().isEmpty)

        try library.replaceBook(stored, with: details, chapters: replacement)
        XCTAssertNil(page(three))
        XCTAssertFalse(env.cache.hasDirectory(for: three), "once the save succeeds, its audio goes")
        XCTAssertFalse(pendingRender(three))
        XCTAssertEqual(ready(two), [0, 2])
        XCTAssertTrue(audioWork().isEmpty, "the work is done and retired")
    }

    /// The folder screen holds the book and the progress recorder holds a chapter's page: after a
    /// failed Replace they read what the store holds, without a fetch or a relaunch, and a later
    /// save writes none of the replacement.
    func testAFailedReplaceLeavesTheBookAndChaptersTheAppHoldsAsTheyWere() throws {
        let book = try addBook()
        let (p1, p2, p3) = (try XCTUnwrap(page(one)), try XCTUnwrap(page(two)), try XCTUnwrap(page(three)))
        library.recordPosition(p2, paragraph: 1, utf16Offset: 3)
        library.recordPlayback(ReaderArticle(page: p3))
        library.recordFinished(p3)
        let finished = try XCTUnwrap(book.finishedAt, "the last chapter finished the book")

        var newDetails = details
        newDetails.byline = "Ben Sample"
        let edited = ["Two begins.", "Two goes on, differently now.", "Two ends."]
        library.saveContext = { _ in throw Died() }
        XCTAssertThrowsError(try library.replaceBook(book, with: newDetails, chapters: [
            chapter(one, 0, "One", textOne), chapter(two, 1, "Two, revised", edited), chapter(UUID(), 2, "Four", ["Four is new."]),
        ])) { XCTAssertEqual($0 as? LibraryStoreError, .saveFailed) }

        XCTAssertFalse(env.context.hasChanges)
        XCTAssertEqual(book.byline, "Ada Example", "the book's details")
        XCTAssertEqual(book.currentPageKey, three, "its place")
        XCTAssertEqual(book.finishedAt, finished, "still finished")
        XCTAssertEqual(Set((book.pages ?? []).compactMap(\.key)), [one, two, three], "its chapters, none inserted")
        XCTAssertEqual(p2.title, "Two")
        XCTAssertEqual(p2.byline, "Ada Example")
        XCTAssertEqual(p2.cachedListenParagraphs, textTwo, "the edited chapter's text")
        XCTAssertEqual(p2.positionParagraph, 1, "and position")
        XCTAssertEqual(p2.positionUTF16, 3)
        XCTAssertFalse(p3.isDeleted, "the dropped chapter")
        XCTAssertTrue(p3.folder === book)
        XCTAssertNotNil(p3.finishedAt)

        library.saveContext = { try $0.save() }
        library.recordPosition(p1, paragraph: 2, utf16Offset: 0)
        let store = ModelContext(env.container)
        let id: UUID? = book.id
        let stored = try store.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.folderID == id }, sortBy: [SortDescriptor(\.sortKey)]))
        XCTAssertEqual(stored.map(\.key), [one, two, three])
        XCTAssertEqual(stored.map(\.positionParagraph), [2, 1, 0], "the later save wrote its own change")
        XCTAssertEqual(stored[1].cachedListenParagraphs, textTwo, "and none of the replacement")
        XCTAssertEqual(stored[1].title, "Two")
    }

    /// The app's progress recorder saves the position when playback stops, and that save commits
    /// whatever the context holds. Replace stops the chapter before changing anything, so when its
    /// own save then fails, the position is all that was saved.
    func testStoppingPlaybackForAReplaceThatFailsSavesOnlyThePosition() throws {
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        let book = try addBook()
        try env.storeAudio(three, paragraphs: textThree)
        let p2 = try XCTUnwrap(page(two))
        library.recordPlayback(ReaderArticle(page: p2))
        library.recordPosition(p2, paragraph: 1, utf16Offset: 2)
        env.playingKey = two
        var failSaves = true
        library.saveContext = { context in
            if failSaves { throw Died() }
            try context.save()
        }
        env.onStop = { [unowned self] key in
            failSaves = false
            defer { failSaves = true }
            library.recordPosition(p2, paragraph: 2, utf16Offset: 3)
            XCTAssertEqual(key, two)
        }

        var newDetails = details
        newDetails.byline = "Ben Sample"
        let edited = ["Two begins.", "Two goes on, differently now.", "Two ends."]
        XCTAssertThrowsError(try library.replaceBook(book, with: newDetails, chapters: [
            chapter(one, 0, "One", textOne), chapter(two, 1, "Two", edited), chapter(UUID(), 2, "Four", ["Four is new."]),
        ]))
        XCTAssertEqual(env.stoppedKeys, [two], "the edited chapter's playback stopped")

        try env.relaunch()
        let stored = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertEqual(library.playOrder(of: stored).map(\.key), [one, two, three], "no chapter dropped or added")
        XCTAssertEqual(stored.byline, "Ada Example", "no detail changed")
        XCTAssertEqual(stored.currentPageKey, two)
        XCTAssertEqual(page(two)?.cachedListenParagraphs, textTwo, "no text changed")
        XCTAssertEqual(page(two)?.positionParagraph, 2, "the position Stop saved")
        XCTAssertEqual(page(two)?.positionUTF16, 3)
        XCTAssertEqual(ready(three), [0, 1, 2], "the dropped chapter's audio")
        XCTAssertTrue(audioWork().isEmpty)
    }

    /// Replace saved, and the app died before the audio work ran. A cold launch on the same files
    /// does the work in the composition's launch step: the dropped chapter's audio and pending
    /// render go, and nothing else.
    func testADeleteLeftByALaunchThatDiedAfterReplaceSavedIsDoneAtTheNextLaunch() throws {
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        let book = try addBook()
        for (key, text) in [(one, textOne), (two, textTwo), (three, textThree)] {
            try env.storeAudio(key, paragraphs: text)
            PendingBakeJobStore.shared.enqueuePending(articleID: key, paragraphs: text, priorityStart: 0)
        }
        let keys = [one, two, three]
        addTeardownBlock { @MainActor in for key in keys { PendingBakeJobStore.shared.removePending(articleID: key) } }
        let web = try library.save(env.article("https://example.com/kept", paragraphs: ["Kept one.", "Kept two."]))
        let webKey = try XCTUnwrap(web.key)
        try env.storeAudio(webKey, paragraphs: ["Kept one.", "Kept two."])
        let four = UUID()

        library.saveContext = { try $0.save(); throw Died() }
        XCTAssertThrowsError(try library.replaceBook(book, with: details, chapters: [
            chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo), chapter(four, 2, "Four", ["Four is new."]),
        ]))
        XCTAssertEqual(ready(three), [0, 1, 2], "died before the work: the audio is still there")

        try env.relaunch()
        XCTAssertEqual(library.playOrder(of: try XCTUnwrap(library.book(key: bookKey))).map(\.key), [one, two, four],
                       "the Replace was saved")
        XCTAssertEqual(audioWork().map(\.kind), [.delete], "with its audio work")
        XCTAssertEqual(audioWork().first?.key, three)

        AppComposition.prepareAudioCache(library: library, migrations: [])
        let cold = ArticleAudioCache(root: env.cache.root)
        XCTAssertFalse(cold.hasDirectory(for: three), "the dropped chapter's audio is gone")
        XCTAssertFalse(pendingRender(three), "and its pending render")
        XCTAssertTrue(audioWork().isEmpty, "the work is retired")
        XCTAssertEqual(env.cache.held, .nothing)
        for key in [one, two] {
            XCTAssertEqual(cold.index(for: key)?.paragraphs.count, 3, "the chapters that stay keep their audio")
            XCTAssertTrue(pendingRender(key), "and their pending renders")
        }
        XCTAssertEqual(cold.index(for: webKey)?.paragraphs.count, 2, "and so does a page outside the book")
    }

    func testADroppedChaptersAudioWaitsBehindEarlierAudioWorkThatCantFinish() throws {
        let book = try addBook()
        try env.storeAudio(three, paragraphs: textThree)
        // A first Replace edits chapter three; aligning its audio fails, so that work waits.
        env.cache.faultHook = { _ in throw Died() }
        let edited = ["Three begins.", "Three goes on, otherwise.", "Three ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                                chapter(three, 2, "Three", edited)])
        XCTAssertEqual(audioWork().map(\.kind), [.align])

        // A second drops the chapter: deleting its audio waits behind the align, which needs it.
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo)])
        XCTAssertNil(page(three))
        XCTAssertEqual(audioWork().map(\.kind), [.align, .delete])
        XCTAssertTrue(env.cache.hasCache(for: three), "not deleted while earlier work on it waits")
        XCTAssertTrue(env.cache.held.contains(three), "and held from the purges, the prune and the D7 trim meanwhile")

        env.cache.faultHook = nil
        XCTAssertEqual(library.finishAudioWork().finished, 2, "next launch: the align, then the delete")
        XCTAssertFalse(env.cache.hasDirectory(for: three))
        XCTAssertFalse(env.cache.held.contains(three))
        XCTAssertTrue(audioWork().isEmpty)
    }

    func testAWaitingDeleteLeavesAChapterThatCameBackAlone() throws {
        let book = try addBook()
        try env.storeAudio(three, paragraphs: textThree)
        env.cache.faultHook = { _ in throw Died() }
        let edited = ["Three begins.", "Three goes on, otherwise.", "Three ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                                chapter(three, 2, "Three", edited)])
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo)])
        // The chapter comes back before the waiting work can run.
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                                chapter(three, 2, "Three", edited)])
        XCTAssertEqual(audioWork().map(\.kind), [.align, .delete])

        env.cache.faultHook = nil
        XCTAssertEqual(library.finishAudioWork().finished, 2)
        XCTAssertNotNil(page(three))
        XCTAssertEqual(ready(three), [0, 2], "its audio is the page's again, aligned, not deleted")
    }

    // MARK: - Finished chapters whose text changed

    func testARevisedFinishedChapterIsUnfinishedAndContinueStartsItFromTheTop() throws {
        let book = try addBook()
        let p2 = try XCTUnwrap(page(two))
        library.recordPlayback(ReaderArticle(page: p2))
        library.recordPosition(p2, paragraph: 2, utf16Offset: 40)
        library.recordFinished(p2)
        XCTAssertEqual(library.continueStart(of: book)?.page.key, three, "before: Continue goes on to chapter three")

        let revised = ["Two begins.", "Two goes on, revised.", "Two ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", revised),
                                                                chapter(three, 2, "Three", textThree)])
        XCTAssertNil(page(two)?.finishedAt, "what was heard isn't what it says now")
        let start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertEqual(start.page.key, two, "Continue plays the revision")
        XCTAssertEqual(start.spot.paragraph, 0, "from its top")
        XCTAssertEqual(start.spot.utf16Offset, 0)
    }

    func testAFinishedBookWhoseLastChapterIsRevisedIsNoLongerFinished() throws {
        let book = try addBook()
        let p3 = try XCTUnwrap(page(three))
        library.recordPlayback(ReaderArticle(page: p3))
        library.recordFinished(p3)
        XCTAssertNotNil(book.finishedAt)

        let revised = ["Three begins.", "Three goes on, revised.", "Three ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", textOne), chapter(two, 1, "Two", textTwo),
                                                                chapter(three, 2, "Three", revised)])
        XCTAssertNil(book.finishedAt)
        let start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertEqual(start.page.key, three, "Continue plays the revised last chapter, not the book from its start")
        XCTAssertEqual(start.spot.paragraph, 0)
    }

    func testAFinishedBookStaysFinishedWhileItsPlaceIsFinishedAndLast() throws {
        let book = try addBook()
        let p3 = try XCTUnwrap(page(three))
        library.recordPlayback(ReaderArticle(page: p3))
        library.recordFinished(p3)
        let finished = try XCTUnwrap(book.finishedAt)

        let revised = ["One begins.", "One goes on, revised.", "One ends."]
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", revised), chapter(two, 1, "Two", textTwo),
                                                                chapter(three, 2, "Three", textThree)])
        XCTAssertEqual(book.finishedAt, finished, "an earlier chapter's revision doesn't unfinish the book")

        let four = UUID()
        try library.replaceBook(book, with: details, chapters: [chapter(one, 0, "One", revised), chapter(two, 1, "Two", textTwo),
                                                                chapter(three, 2, "Three", textThree),
                                                                chapter(four, 3, "Four", ["Four is new."])])
        XCTAssertNil(book.finishedAt, "a chapter after its place: there is more to hear")
        XCTAssertEqual(library.continueStart(of: book)?.page.key, four)
    }

    func testTheD7TrimLeavesTheAudioOfARevisedFinishedChapter() throws {
        let four = UUID(), five = UUID()
        let textFour = ["Four begins.", "Four goes on.", "Four ends."]
        let textFive = ["Five begins.", "Five goes on.", "Five ends."]
        func chapters(one textOfOne: [String]) -> [PageContent] {
            [chapter(one, 0, "One", textOfOne), chapter(two, 1, "Two", textTwo), chapter(three, 2, "Three", textThree),
             chapter(four, 3, "Four", textFour), chapter(five, 4, "Five", textFive)]
        }
        let book = try library.addBook(details, chapters: chapters(one: textOne), in: nil)
        try env.storeAudio(one, paragraphs: textOne)
        try env.storeAudio(two, paragraphs: textTwo)
        for key in [one, two] {
            let p = try XCTUnwrap(page(key))
            library.recordPlayback(ReaderArticle(page: p))
            library.recordFinished(p)
        }

        let revised = ["One begins.", "One goes on, revised.", "One ends."]
        try library.replaceBook(book, with: details, chapters: chapters(one: revised))
        XCTAssertEqual(ready(one), [0, 2], "the revision keeps the audio of what reads the same")
        library.recordPlaybackStarted(try XCTUnwrap(page(five)))
        XCTAssertFalse(env.cache.hasCache(for: two), "a finished chapter more than 2 behind loses its audio")
        XCTAssertEqual(ready(one), [0, 2], "the revised one, unheard, keeps it")
    }

    func testANewBookIsKeptWholeOrNotAtAll() throws {
        library.saveContext = { _ in throw CocoaError(.fileWriteUnknown) }
        XCTAssertThrowsError(try addBook()) { XCTAssertEqual($0 as? LibraryStoreError, .saveFailed) }
        XCTAssertTrue(env.folders().isEmpty)
        XCTAssertTrue(env.pages().isEmpty)
    }

    func testAPositionLandsOnTheNearestParagraphWithItsText() {
        let new = ParagraphDocument(parts: ["Same.", "Other.", "Same.", "Last."])
        let at = LibraryStore.carriedPosition(paragraph: 2, utf16Offset: 16, from: ["Intro.", "Same.", "Same."], to: new)
        XCTAssertEqual(at?.paragraph, 2)
        XCTAssertEqual(at?.utf16Offset, new.utf16Ranges[2].location + 1)
        XCTAssertNil(LibraryStore.carriedPosition(paragraph: 0, utf16Offset: 0, from: ["Gone."], to: new))
    }
}
