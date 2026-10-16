import XCTest
@testable import MeridianReader

/// The address field's one rule: what Submit loads as an address, and what it searches for (and
/// the search suggestions ask Google about).
final class BrowseURLParserTests: XCTestCase {
    private let searches = ["3.14", "e.g.", "v1.2", "best pizza", "swift 6.2 release", "localhost:8080", "a.b", "1.2.3"]
    private let addresses: [(typed: String, loads: String)] = [
        ("example.com", "https://example.com"),
        ("node.js", "https://node.js"),
        ("sub.example.co.uk", "https://sub.example.co.uk"),
        ("example.com/post?id=1", "https://example.com/post?id=1"),
        ("example.com:8080", "https://example.com:8080"),
        ("example.com.", "https://example.com."),
        ("192.168.1.10", "https://192.168.1.10"),
        ("10.0.0.1:8080/admin", "https://10.0.0.1:8080/admin"),
        ("https://example.com/a", "https://example.com/a"),
        ("http://localhost:8080", "http://localhost:8080"),
    ]

    func testTextThatIsNoAddressIsSearched() throws {
        for text in searches {
            XCTAssertTrue(BrowseURLParser.isSearch(text), text)
            let url = try XCTUnwrap(BrowseURLParser.destination(from: text), text)
            XCTAssertEqual(url.host, "www.google.com", text)
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, text)
        }
    }

    func testAddressesLoadAsTyped() {
        for (typed, loads) in addresses {
            XCTAssertFalse(BrowseURLParser.isSearch(typed), typed)
            XCTAssertEqual(BrowseURLParser.destination(from: typed)?.absoluteString, loads, typed)
        }
    }

    /// The suggestions layer asks Google about exactly the text Submit would search for.
    func testSuggestionsFollowTheSameRule() {
        for text in searches {
            XCTAssertEqual(GoogleSuggestClient.query(forTyped: text, enabled: true), text, text)
        }
        for (typed, _) in addresses {
            XCTAssertNil(GoogleSuggestClient.query(forTyped: typed, enabled: true), typed)
        }
    }

    func testEmptyTextGoesNowhere() {
        XCTAssertNil(BrowseURLParser.destination(from: "  "))
        XCTAssertFalse(BrowseURLParser.isSearch("  "))
    }
}
