import XCTest
@testable import Reader

/// The rule for books and series (`ChapterAdvance`): a chapter carries on to the next playable
/// one, and Continue starts at the book's place. Pure, then on the library's snapshot.
@MainActor
final class ChapterAdvanceTests: XCTestCase {
    private typealias Chapter = ChapterAdvance.Chapter

    private let keys = (0..<6).map { _ in UUID() }

    private func chapters(_ edit: (inout [Chapter]) -> Void = { _ in }) -> [Chapter] {
        var list = keys.map { Chapter(key: $0) }
        edit(&list)
        return list
    }

    // MARK: Carrying on

    func testAChapterGoesToTheNextPlayableOne() {
        XCTAssertEqual(ChapterAdvance.after(keys[0], in: chapters()), .ready(keys[1]))
        XCTAssertEqual(ChapterAdvance.decide(.ready(keys[1])), .play(keys[1]))
    }

    func testSkippedChaptersArePassedOver() {
        let list = chapters { $0[1].skipsInPlayback = true; $0[2].skipsInPlayback = true }
        XCTAssertEqual(ChapterAdvance.after(keys[0], in: list), .ready(keys[3]))
        // A chapter marked skipped while it played is still found, so playback goes on after it.
        XCTAssertEqual(ChapterAdvance.after(keys[1], in: list), .ready(keys[3]))
    }

    func testTheLastChapterEnds() {
        XCTAssertEqual(ChapterAdvance.after(keys[5], in: chapters()), ChapterAdvance.Next.none)
        let skippedTail = chapters { $0[4].skipsInPlayback = true; $0[5].skipsInPlayback = true }
        XCTAssertEqual(ChapterAdvance.after(keys[3], in: skippedTail), ChapterAdvance.Next.none, "only skipped chapters after it")
        XCTAssertEqual(ChapterAdvance.decide(.none), .end(notice: nil), "the end of the book: no notice")
    }

    func testAPageInNoFolderEnds() {
        XCTAssertEqual(ChapterAdvance.after(UUID(), in: []), ChapterAdvance.Next.none)
        XCTAssertEqual(ChapterAdvance.after(UUID(), in: chapters()), ChapterAdvance.Next.none, "not one of the chapters")
    }

    func testALinkChapterWaitsForItsFetch() {
        let list = chapters { $0[1].isLink = true }
        XCTAssertEqual(ChapterAdvance.after(keys[0], in: list), .pending(keys[1]))
        XCTAssertEqual(ChapterAdvance.decide(.pending(keys[1])), .waitForFetch(keys[1]))
    }

    func testALockedChapterEndsWithItsNotice() {
        let list = chapters { $0[1].isLink = true; $0[1].blockedReason = "Next chapter is locked" }
        XCTAssertEqual(ChapterAdvance.after(keys[0], in: list), .unavailable(reason: "Next chapter is locked"))
        XCTAssertEqual(ChapterAdvance.decide(.unavailable(reason: "Next chapter is locked")),
                       .end(notice: "Next chapter is locked"))
    }

    // MARK: Continue

    func testStartWithNoPlaceIsTheFirstPlayableChapter() {
        let list = chapters { $0[0].skipsInPlayback = true }
        XCTAssertEqual(ChapterAdvance.start(list, place: nil), .ready(keys[1]), "front matter skipped")
    }

    func testStartResumesAnUnfinishedPlace() {
        XCTAssertEqual(ChapterAdvance.start(chapters(), place: keys[3]), .ready(keys[3]))
    }

    func testStartMovesPastAFinishedPlace() {
        let list = chapters { $0[3].isFinished = true; $0[4].skipsInPlayback = true }
        XCTAssertEqual(ChapterAdvance.start(list, place: keys[3]), .ready(keys[5]))
    }

    func testStartRestartsAFinishedBook() {
        let list = chapters { list in
            for i in list.indices { list[i].isFinished = true }
            list[0].skipsInPlayback = true
        }
        XCTAssertEqual(ChapterAdvance.start(list, place: keys[5]), .ready(keys[1]), "from its first playable chapter")
    }

    // MARK: On the library

    /// Continue on a book: the place at its saved spot while unfinished, the next chapter from
    /// its start once finished, and a finished book from its first chapter, no longer finished.
    func testContinueResumesThePlaceMovesPastItAndRestartsAFinishedBook() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        let library: LibraryStore = env.library
        let (book, pages) = Self.seedBook(in: library, titles: ["Title Page", "One", "Two", "Three"], skipFirst: true)

        var start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertTrue(start.page === pages[1], "no place yet: the first chapter after the title page")
        XCTAssertEqual(start.paragraph, 0)

        book.currentPageKey = pages[2].key
        pages[2].positionParagraph = 1
        pages[2].positionUTF16 = 40
        start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertTrue(start.page === pages[2], "the place")
        XCTAssertEqual(start.paragraph, 1, "at its spot")
        XCTAssertEqual(start.utf16Offset, 40)

        pages[2].finishedAt = env.now
        start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertTrue(start.page === pages[3], "past a finished place")
        XCTAssertEqual(start.paragraph, 0, "from its start")

        book.currentPageKey = pages[3].key
        pages[3].finishedAt = env.now
        book.finishedAt = env.now
        start = try XCTUnwrap(library.continueStart(of: book))
        XCTAssertTrue(start.page === pages[1], "a finished book starts again")
        XCTAssertNil(book.finishedAt, "and is no longer finished")
    }

    func testTheSnapshotFlagsSkippedLinkAndBlockedChapters() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        let library: LibraryStore = env.library
        let series = Folder(name: "Serial", kind: .series)
        env.context.insert(series)
        let saved = Page(key: UUID(), title: "One", byline: "", urlString: "https://example.com/s/1",
                         contentState: .saved, addedAt: env.now, sortKey: 0)
        let link = Page(key: UUID(), title: "Two", byline: "", urlString: "https://example.com/s/2",
                        contentState: .link, addedAt: env.now, sortKey: 1)
        let locked = Page(key: UUID(), title: "Three", byline: "", urlString: "https://example.com/s/3",
                          contentState: .link, addedAt: env.now, sortKey: 2)
        locked.fetchState = .locked
        for page in [saved, link, locked] {
            env.context.insert(page)
            page.setFolder(series)
        }
        let snapshot = library.chapterSnapshot(of: series)
        XCTAssertEqual(snapshot.map(\.key), [saved.key, link.key, locked.key], "in play order")
        XCTAssertEqual(ChapterAdvance.after(saved.listenKey, in: snapshot), .pending(link.listenKey))
        XCTAssertEqual(ChapterAdvance.after(link.listenKey, in: snapshot), .unavailable(reason: "Next chapter is locked"))

        let plain = Folder(name: "Mine")
        env.context.insert(plain)
        XCTAssertTrue(library.chapterSnapshot(of: plain).isEmpty, "a folder you made doesn't carry on")
    }

    /// A book of saved chapters with `titles`, the first one skipped when `skipFirst`.
    static func seedBook(in library: LibraryStore, titles: [String], skipFirst: Bool = false,
                         paragraphs: [String] = ["A first paragraph.", "A second paragraph.", "A third paragraph."])
        -> (Folder, [Page]) {
        let book = Folder(name: "The Book", kind: .book)
        book.byline = "An Author"
        library.context.insert(book)
        let pages = titles.enumerated().map { index, title in
            let page = Page(key: UUID(), title: title, byline: "An Author", urlString: nil, contentState: .saved,
                            addedAt: .now, sortKey: Double(index))
            page.plainText = paragraphs.map { "\(title). \($0)" }.joined(separator: "\n\n")
            page.storeListenParagraphs(paragraphs.map { "\(title). \($0)" })
            page.skipsInPlayback = skipFirst && index == 0
            library.context.insert(page)
            page.setFolder(book)
            return page
        }
        library.commit("seed book")
        return (book, pages)
    }
}
