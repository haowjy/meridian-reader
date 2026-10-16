import SwiftData
import XCTest
@testable import MeridianReader

/// Books and series are folders like any other (decision D19). *Replace* finds a book's chapters
/// by key wherever they were moved, keeps your order and puts new chapters beside their
/// neighbours, and never touches pages moved in from elsewhere; a series' new chapters append at
/// the end and find the ones it has by address; a book stored before books kept a record of
/// their chapters gets one at launch and keeps everything else.
@MainActor
final class BookAsFolderTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }
    private let bookKey = UUID()
    private let keys = (0..<6).map { _ in UUID() }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private var details: FolderDetails {
        FolderDetails(kind: .book, title: "The Book", byline: "Ada Example", cover: nil, sourceURL: nil,
                      sourceIdentifier: bookKey.uuidString,
                      sourceState: try? JSONEncoder().encode(BookSourceState(fileFingerprint: "abc")))
    }

    private func text(_ n: Int, _ edit: String = "") -> [String] {
        ["Chapter \(n) begins.", "Chapter \(n) goes on\(edit).", "Chapter \(n) ends."]
    }

    /// Chapter `n` of the file, at `ordinal`, under `keys[n]` unless `key` says otherwise.
    private func chapter(_ n: Int, at ordinal: Int, key: UUID? = nil, edit: String = "") -> PageContent {
        let ref = PageRef(key: key ?? keys[n], locator: .book(EPUBLocator(href: "OEBPS/c\(n).xhtml", anchor: .fileStart)),
                          ordinal: ordinal, title: "Ch \(n)")
        return PageContent(ref: ref, title: "Ch \(n)", bodyHTML: text(n, edit).map { "<p>\($0)</p>" }.joined(),
                           plainText: text(n, edit).joined(separator: "\n\n"), excerpt: "")
    }

    private func edition(_ numbers: [Int]) -> [PageContent] {
        numbers.enumerated().map { chapter($1, at: $0) }
    }

    private func page(_ n: Int) throws -> Page { try XCTUnwrap(library.page(key: keys[n]), "chapter \(n)") }

    private func titles(_ folder: Folder) -> [String] { library.playOrder(of: folder).map(\.title) }

    private func assertOnePagePerKey(file: StaticString = #filePath, line: UInt = #line) {
        let stored = env.pages().compactMap(\.key)
        XCTAssertEqual(Set(stored).count, stored.count, "no key made twice", file: file, line: line)
    }

    // MARK: - Replace

    /// Reordered, with a chapter dropped from the new file, a new one added after chapter 1 and a
    /// page of yours moved in: your order stays, the new chapter goes after chapter 1, the dropped
    /// one goes, and your page is untouched.
    func testReplaceAfterAReorderKeepsYourOrderAndSlotsNewChaptersBesideTheirNeighbours() throws {
        let book = try library.addBook(details, chapters: edition([0, 1, 2, 3]), in: nil)
        XCTAssertEqual(titles(book), ["Ch 0", "Ch 1", "Ch 2", "Ch 3"], "first in the book's order")
        try library.arrange([page(3)], in: book, before: page(0), shownIn: .manual)
        let mine = try library.save(env.article("https://example.com/mine", title: "Mine"))
        try library.move([.page(mine)], to: book)
        XCTAssertEqual(titles(book), ["Ch 3", "Ch 0", "Ch 1", "Ch 2", "Mine"])

        try library.replaceBook(book, with: details, chapters: edition([0, 1, 4, 2]))
        XCTAssertEqual(titles(book), ["Ch 0", "Ch 1", "Ch 4", "Ch 2", "Mine"])
        XCTAssertNil(library.page(key: keys[3]), "the chapter the file dropped")
        XCTAssertIdentical(mine.folder, book, "a page moved in is never touched")
        XCTAssertTrue(mine.isSavedToLibrary)
        XCTAssertEqual(book.bookState?.chapterKeys, [keys[0], keys[1], keys[4], keys[2]], "the new record")
        XCTAssertEqual(book.bookState?.fileFingerprint, "abc")
        assertOnePagePerKey()

        // A new first chapter goes before the first chapter in the book, wherever that is now.
        try library.arrange([page(2)], in: book, before: page(0), shownIn: .manual)
        try library.replaceBook(book, with: details, chapters: edition([5, 0, 1, 4, 2]))
        XCTAssertEqual(titles(book), ["Ch 2", "Ch 5", "Ch 0", "Ch 1", "Ch 4", "Mine"])
    }

    /// A chapter moved out of the book is still the book's: *Replace* brings its text up to date
    /// where it is and makes no second page; one the file dropped stays where it was put.
    func testReplaceFindsChaptersMovedOutAndLeavesThemWhereTheyWerePut() throws {
        let book = try library.addBook(details, chapters: edition([0, 1, 2]), in: nil)
        let elsewhere = try library.makeFolder(name: "Elsewhere", in: nil)
        try library.move([.page(page(1)), .page(page(2))], to: elsewhere)
        library.recordPosition(try page(1), paragraph: 2, utf16Offset: 0)

        try library.replaceBook(book, with: details, chapters: [chapter(0, at: 0), chapter(1, at: 1, edit: " differently")])
        XCTAssertEqual(titles(book), ["Ch 0"], "no second copy of a chapter moved out")
        XCTAssertEqual(titles(elsewhere), ["Ch 1", "Ch 2"])
        XCTAssertEqual(try page(1).cachedListenParagraphs, text(1, " differently"), "updated where it is")
        XCTAssertEqual(try page(1).positionParagraph, 2, "its paragraph is still there, word for word")
        XCTAssertFalse(try page(2).isDeleted, "a dropped chapter moved out stays")
        assertOnePagePerKey()
    }

    /// The same text under a new key, for a chapter moved out: the new page takes the old one's
    /// folder, place in the order and position.
    func testAChapterMovedOutAndRekeyedTakesItsPlaceThere() throws {
        let book = try library.addBook(details, chapters: edition([0, 1]), in: nil)
        let elsewhere = try library.makeFolder(name: "Elsewhere", in: nil)
        let before = try library.save(env.article("https://example.com/before", title: "Before"))
        try library.move([.page(before), .page(page(1))], to: elsewhere)
        library.recordPosition(try page(1), paragraph: 1, utf16Offset: 0)
        let rekeyed = UUID()

        try library.replaceBook(book, with: details, chapters: [chapter(0, at: 0), chapter(1, at: 1, key: rekeyed)])
        XCTAssertNil(library.page(key: keys[1]))
        let moved = try XCTUnwrap(library.page(key: rekeyed))
        XCTAssertIdentical(moved.folder, elsewhere)
        XCTAssertEqual(titles(elsewhere), ["Before", "Ch 1"])
        XCTAssertEqual(moved.positionParagraph, 1)
        XCTAssertEqual(titles(book), ["Ch 0"])
    }

    /// A chapter removed from the Library (waiting for the prune) comes back into the book, in
    /// its place, when the book is replaced.
    func testARemovedChapterComesBackIntoTheBook() throws {
        let book = try library.addBook(details, chapters: edition([0, 1, 2]), in: nil)
        try library.remove([page(1)])
        XCTAssertEqual(titles(book), ["Ch 0", "Ch 2"])

        try library.replaceBook(book, with: details, chapters: edition([0, 1, 2]))
        XCTAssertEqual(titles(book), ["Ch 0", "Ch 1", "Ch 2"])
        XCTAssertTrue(try page(1).isInLibrary)
        assertOnePagePerKey()
    }

    /// A book deleted after a chapter was moved out of it, then imported again: the chapter stays
    /// where it is, brought up to date, and the new book holds the rest in order.
    func testImportingABookAgainKeepsAChapterThatOutlivedTheOldCopy() throws {
        let book = try library.addBook(details, chapters: edition([0, 1, 2]), in: nil)
        let elsewhere = try library.makeFolder(name: "Elsewhere", in: nil)
        try library.move([.page(page(1))], to: elsewhere)
        try library.deleteFolder(book)
        XCTAssertNil(library.book(key: bookKey))

        let again = try library.addBook(details, chapters: edition([0, 1, 2]), in: nil)
        XCTAssertEqual(titles(again), ["Ch 0", "Ch 2"])
        XCTAssertIdentical(try page(1).folder, elsewhere)
        XCTAssertEqual(again.bookState?.chapterKeys, [keys[0], keys[1], keys[2]], "all three are the book's")
        assertOnePagePerKey()
    }

    // MARK: - Books stored before the record

    /// A book stored before books kept a record of their chapters (its state holds only the
    /// file's fingerprint) gets one at launch from the pages in it, in their order, once. Its
    /// chapters, order, details and listening read as they did, after a relaunch too; and once
    /// recorded, *Replace* leaves a page moved into it alone.
    func testABookStoredWithoutARecordGetsOneAndKeepsEverything() throws {
        env.cleanUp()
        env = try LibraryTestEnvironment(fileBacked: true)
        let book = try library.addBook(details, chapters: edition([0, 1, 2]), in: nil)
        book.sourceStateData = Data(#"{"fileFingerprint":"abc"}"#.utf8)
        book.coverData = Data([1, 2, 3])
        library.recordPlayback(ReaderArticle(page: try page(1)))
        library.recordPosition(try page(1), paragraph: 2, utf16Offset: 4)
        library.recordFinished(try page(0))
        try env.context.save()
        try env.relaunch()

        let stored = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertNil(stored.bookState?.chapterKeys, "no record yet")
        XCTAssertEqual(library.recordBookChapters(), 1)
        XCTAssertEqual(library.recordBookChapters(), 0, "once")
        try env.relaunch()

        let book2 = try XCTUnwrap(library.book(key: bookKey))
        XCTAssertEqual(book2.bookState, BookSourceState(fileFingerprint: "abc", chapterKeys: [keys[0], keys[1], keys[2]]))
        XCTAssertEqual(titles(book2), ["Ch 0", "Ch 1", "Ch 2"], "its chapters, in order")
        XCTAssertEqual(book2.pageSort, .manual)
        XCTAssertEqual(book2.byline, "Ada Example")
        XCTAssertEqual(book2.coverData, Data([1, 2, 3]))
        XCTAssertEqual(book2.currentPageKey, keys[1], "its place")
        XCTAssertEqual(try page(1).positionParagraph, 2)
        XCTAssertEqual(try page(1).positionUTF16, 4)
        XCTAssertNotNil(try page(0).finishedAt)

        let mine = try library.save(env.article("https://example.com/mine", title: "Mine"))
        try library.move([.page(mine)], to: book2)
        try library.replaceBook(book2, with: details, chapters: edition([0, 1, 2]))
        XCTAssertIdentical(mine.folder, book2, "a page moved in after the record is never the book's chapter")
        XCTAssertEqual(titles(book2), ["Ch 0", "Ch 1", "Ch 2", "Mine"])
        XCTAssertEqual(try page(1).positionParagraph, 2)
    }
}
