import XCTest
@testable import MeridianReader

final class AddressSuggestionsTests: XCTestCase {
    private struct Page: AddressSuggestionSource {
        var id = UUID()
        var title: String
        var suggestionHost: String
        var urlString: String
        var faviconData: Data? = nil
    }

    private func page(_ title: String, _ url: String) -> Page {
        Page(title: title, suggestionHost: URL(string: url)?.host ?? "", urlString: url)
    }

    func testEmptyQuerySuggestsNothing() {
        let visits = [page("Swift", "https://swift.org/")]
        XCTAssertEqual(AddressSuggestions.build(query: "  ", visits: visits, articles: [Page](), google: ["x"]), [])
    }

    func testHistoryThenSavedThenGoogleDedupedCaseInsensitively() {
        let visits = [page("Swift blog", "https://swift.org/blog"), page("Other", "https://example.com/")]
        let articles = [page("Swift concurrency", "https://SWIFT.org/blog"), page("Swift macros", "https://swift.org/macros")]
        let rows = AddressSuggestions.build(query: "swift", visits: visits, articles: articles,
                                            google: ["swift tutorial", "Swift Tutorial"])
        XCTAssertEqual(rows.map(\.kind), [.recent, .saved, .google])
        XCTAssertEqual(rows.map(\.query), ["https://swift.org/blog", "https://swift.org/macros", "swift tutorial"])
        XCTAssertEqual(rows.last?.subtitle, "Google Search")
    }

    func testMatchesTitleHostOrURL() {
        let visits = [page("Front page", "https://news.ycombinator.com/"), page("Unrelated", "https://a.com/x")]
        XCTAssertEqual(AddressSuggestions.build(query: "ycomb", visits: visits, articles: [Page](), google: []).count, 1)
        XCTAssertEqual(AddressSuggestions.build(query: "front", visits: visits, articles: [Page](), google: []).count, 1)
    }

    func testCaps() {
        let visits = (0..<10).map { page("Hit \($0)", "https://h\($0).com/") }
        let articles = (0..<10).map { page("Hit saved \($0)", "https://s\($0).com/") }
        let google = (0..<20).map { "hit \($0)" }
        let rows = AddressSuggestions.build(query: "hit", visits: visits, articles: articles, google: google)
        XCTAssertEqual(rows.filter { $0.kind == .recent }.count, AddressSuggestions.maxVisits)
        XCTAssertEqual(rows.filter { $0.kind == .saved }.count, AddressSuggestions.maxSaved)
        XCTAssertEqual(rows.count, AddressSuggestions.maxRows)
    }

    func testURLHelpers() {
        let a = URL(string: "https://Example.com/post/#comments")!
        XCTAssertTrue(a.isWeb)
        XCTAssertTrue(a.isSamePage(as: URL(string: "https://example.com/post")!))
        XCTAssertFalse(a.isSamePage(as: URL(string: "https://example.com/other")!))
        XCTAssertFalse(URL(string: "about:blank")!.isWeb)
        XCTAssertFalse(URL(string: "reader-test://pages/one")!.isWeb)
    }
}
