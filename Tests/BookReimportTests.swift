import XCTest
@testable import Reader

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
        library.keyMerged = { [unowned self] in merged.append(($0, $1)) }
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
        XCTAssertNil(book.currentPageKey, "the place it held is cleared")
        XCTAssertEqual(library.playOrder(of: book).map(\.key), [one, two, four])
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
