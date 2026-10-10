import SwiftData
import XCTest
@testable import MeridianReader

/// Continue: pages part-way through, most recently played first (`LibraryQueries.continuePages`).
@MainActor
final class ContinueListeningTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws { container = try LibraryStoreConfiguration.makeInMemoryContainer() }

    private func page(added: TimeInterval = 0, played: TimeInterval? = nil, finished: Bool = false, p: Int = 0,
                      off: Int = 0, n: Int = 10, state: PageContentState = .saved, inLibrary: Bool = true) -> Page {
        let page = Page(key: UUID(), title: "P", byline: "example.com", urlString: "https://example.com/\(UUID())",
                        contentState: state, addedAt: inLibrary ? Date(timeIntervalSince1970: added) : nil)
        container.mainContext.insert(page)
        page.lastPlayedAt = played.map(Date.init(timeIntervalSince1970:))
        page.finishedAt = finished ? page.lastPlayedAt : nil
        page.positionParagraph = p
        page.positionUTF16 = off
        page.paragraphCount = n
        return page
    }

    private func continuing(_ pages: [Page]) -> [Page] {
        LibraryQueries.continuePages(recent: pages.filter { $0.lastPlayedAt != nil },
                                     undated: pages.filter { $0.lastPlayedAt == nil })
    }

    func testUnstartedPagesAreNotInProgress() {
        XCTAssertTrue(continuing([page(), page(added: 5)]).isEmpty)
    }

    func testUndatedProgressCountsUnlessParkedAtTheEnd() {
        let mid = page(p: 3), end = page(p: 9, n: 10), unknown = page(p: 2, n: 0)
        XCTAssertEqual(Set(continuing([mid, end, unknown]).map(\.key)), [mid.key, unknown.key])
    }

    func testPlayedOrdersByMostRecentAndFinishedDropsOut() {
        let a = page(added: 30, played: 300, finished: true, p: 1)
        let b = page(added: 20, played: 200) // listened at paragraph 0 still counts
        let d = page(added: 10, played: 100, p: 4)
        let undated = page(added: 40, p: 2)
        XCTAssertEqual(continuing([a, b, d, undated]).map(\.key), [b.key, d.key, undated.key], "dated first")
        a.finishedAt = nil // replayed: back in progress, first
        XCTAssertEqual(continuing([a, b, d, undated]).map(\.key), [a.key, b.key, d.key, undated.key])
    }

    func testLinksAndChaptersStayOutButPagesNotInTheLibraryShow() {
        let link = page(played: 100, state: .link)
        let notInLibrary = page(played: 200, inLibrary: false)
        let book = Folder(name: "Book", kind: .book)
        container.mainContext.insert(book)
        let chapter = page(played: 300, p: 2)
        chapter.setFolder(book)
        XCTAssertEqual(continuing([link, notInLibrary, chapter]).map(\.key), [notInLibrary.key])
    }

    /// Pages played without saving: Continue on the Library home lists every one (up to its eight
    /// cards), the oldest too, leaving them out of the Library and unfiled.
    func testContinueListsEveryCandidateIncludingPagesNotInTheLibrary() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        var played: [UUID] = []
        for i in 0..<5 {
            env.now = Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60)
            let page = env.library.recordPlayback(env.article("https://example.com/played-\(i)", title: "Played \(i)"))
            played.append(page.listenKey)
        }
        let newestFirst = Array(played.reversed())
        let all = LibraryQueries.continuePages(recent: try env.context.fetch(LibraryQueries.recentlyPlayed),
                                               undated: try env.context.fetch(LibraryQueries.undatedInProgress))
        XCTAssertEqual(all.map(\.listenKey), newestFirst, "every candidate, most recent first")

        let items = LibraryQueries.continueItems(folders: [], recent: try env.context.fetch(LibraryQueries.recentlyPlayed),
                                                 undated: try env.context.fetch(LibraryQueries.undatedInProgress))
        XCTAssertEqual(items.compactMap { item -> UUID? in
            if case .page(let page) = item { return page.listenKey }
            return nil
        }, newestFirst, "the Library's Continue cards reach the oldest too")

        XCTAssertTrue(all.allSatisfy { !$0.isInLibrary && $0.folder == nil }, "listed, not saved or moved")
        XCTAssertTrue(try env.context.fetch(LibraryQueries.loosePages(sort: .newest)).isEmpty,
                      "the Library's Pages can't show them, so Continue does")
    }

    func testRowProgressIsWeightedByTextLength() {
        // 100 + 300 + 100 UTF-16 units; listen text joins them with "\n\n" (starts 0, 102, 404).
        let paragraphs = [String(repeating: "a", count: 100), String(repeating: "b", count: 300),
                          String(repeating: "c", count: 100)]
        func progress(_ p: Int, _ offset: Int) -> Double {
            PageProgress.fraction(paragraphs: paragraphs, paragraph: p, utf16Offset: offset)
        }
        XCTAssertEqual(progress(0, 0), 0, accuracy: 1e-9)
        XCTAssertEqual(progress(1, 102 + 150), 0.5, accuracy: 1e-9, "halfway through the long middle paragraph")
        XCTAssertEqual(progress(9, 404), 0.8, accuracy: 1e-9, "paragraph index clamps to the last one")
        XCTAssertLessThan(progress(0, 101), 0.2, "a paragraph's end never reads as the next one's start")
        XCTAssertEqual(PageProgress.fraction(paragraphs: [], paragraph: 0, utf16Offset: 0), 0)
    }
}
