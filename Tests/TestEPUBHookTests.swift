import XCTest
@testable import Reader

/// `-importTestEPUB`: the synthetic EPUB goes through the real import into the top level, fresh
/// each launch, and plays from chapter 1, not its title page.
@MainActor
final class TestEPUBHookTests: XCTestCase {
    func testTheTestBookImportsFreshAtTheTopLevelAndStartsAtChapterOne() async throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        let library: LibraryStore = env.library
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let maybeBook = await LaunchHooks.importTestEPUB(in: library)
        let book = try XCTUnwrap(maybeBook)
        XCTAssertNil(book.parent, "at the top level")
        XCTAssertEqual(book.name, TestEPUB.title)
        XCTAssertEqual(book.sourceIdentifier, TestEPUB.bookKey.uuidString)
        XCTAssertEqual(library.topLevelFolders().map(\.name), ["Shelf", TestEPUB.title])
        XCTAssertTrue(library.pages(in: shelf).isEmpty)

        let pages = library.playOrder(of: book)
        let keys = pages.map(\.key)
        XCTAssertEqual(pages.map(\.title), ["Title Page"] + TestEPUB.chapterTitles)
        XCTAssertEqual(pages.map(\.skipsInPlayback), [true, false, false, false])
        let one = pages[1]
        let blocks = try XCTUnwrap(one.cachedListenParagraphs)
        XCTAssertEqual(Array(blocks.prefix(3)), [TestEPUB.chapterTitles[0], TestEPUB.looseLine,
                                                 DemoBook.chapters[1].paragraphs[0]])
        XCTAssertEqual(blocks.last, "The end of the chapter.")
        XCTAssertFalse(blocks.contains(TestEPUB.footnote))
        XCTAssertEqual(library.continueStart(of: book)?.page.title, TestEPUB.chapterTitles[0])

        // Played part-way, then launched again: a fresh book, unplayed.
        library.recordPlayback(ReaderArticle(page: one))
        library.recordPosition(one, paragraph: 3, utf16Offset: 0)
        let againOrNil = await LaunchHooks.importTestEPUB(in: library)
        let again = try XCTUnwrap(againOrNil)
        XCTAssertEqual(env.folders().filter { $0.kind == .book }.count, 1)
        XCTAssertNil(again.currentPageKey)
        XCTAssertEqual(library.playOrder(of: again).map(\.positionParagraph), [0, 0, 0, 0])
        XCTAssertEqual(library.playOrder(of: again).map(\.key), keys, "the same file, the same keys")
    }
}
