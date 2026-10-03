import XCTest
@testable import Reader

/// The reader overlay returns to the browser as it is underneath (the page, or the start page),
/// and its back control names that place.
@MainActor
final class ReaderOriginTests: XCTestCase {
    private let pageURL = URL(string: "https://example.com/post")!

    private func article() -> ReaderArticle {
        ReaderArticle(id: UUID(), url: pageURL,
                      extracted: ExtractedArticle(title: "Post", siteName: nil, cleanedHTML: "<p>Hello there.</p>",
                                                  plainText: "Hello there.", excerpt: ""))
    }

    private func readerOrigin(_ shell: ShellState) -> ReaderOrigin? {
        if case .reader(_, let origin) = shell.surface { origin } else { nil }
    }

    func testOpenedOverTheStartPageGoesBackToIt() {
        let shell = ShellState()
        shell.showReader(article())
        XCTAssertEqual(readerOrigin(shell), .startPage)
        shell.hideReader()
        XCTAssertTrue(shell.isBrowsing)
        XCTAssertFalse(shell.web.hasPage, "still the start page")
    }

    func testOpenedOverAPageGoesBackToThatPage() {
        let shell = ShellState()
        shell.web.load(pageURL)
        shell.showReader(article())
        XCTAssertEqual(readerOrigin(shell), .page)
        shell.hideReader()
        XCTAssertTrue(shell.isBrowsing)
        XCTAssertEqual(shell.web.currentURL, pageURL, "the page is still loaded")
    }

    func testBackControlNamesWhereItGoes() {
        XCTAssertEqual(ReaderOrigin.page.backLabel, "Back to Website")
        XCTAssertEqual(ReaderOrigin.startPage.backLabel, "Back to Start Page")
        XCTAssertEqual(ReaderOrigin.library.backLabel, "Back to Library")
        XCTAssertEqual(Set([ReaderOrigin.page, .startPage, .library].map(\.backSystemImage)).count, 3,
                       "each place has its own icon")
    }
}
