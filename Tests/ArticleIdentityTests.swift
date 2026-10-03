import XCTest
@testable import Reader

/// One article per canonical URL: tracking parameters, fragments and host case never make a
/// second article (or a second Saved row) for the same page.
final class ArticleIdentityTests: XCTestCase {
    func testCanonicalURLDropsTrackingParamsFragmentAndHostCase() {
        let canonical = "https://www.example.com/stories/1?page=2"
        for variant in [
            "https://www.example.com/stories/1?page=2",
            "https://WWW.Example.com/stories/1?page=2#comments",
            "https://www.example.com/stories/1?utm_source=home&page=2&utm_medium=latest",
            "https://www.example.com/stories/1/?page=2&fbclid=abc",
            "https://www.example.com:443/stories/1?page=2",
        ] {
            XCTAssertEqual(ArticleIdentity.canonicalURLString(from: variant), canonical, variant)
        }
        XCTAssertEqual(ArticleIdentity.canonicalURLString(from: "https://example.com/"), "https://example.com/",
                       "the root path keeps its slash")
    }

    func testArticleKeyIsStableAcrossTrackingVariants() {
        let plain = ArticleIdentity.articleKey(url: URL(string: "https://example.com/a")!)
        XCTAssertEqual(ArticleIdentity.articleKey(url: URL(string: "https://example.com/a?utm_campaign=x#top")!), plain)
        XCTAssertNotEqual(ArticleIdentity.articleKey(url: URL(string: "https://example.com/b")!), plain)
        XCTAssertNotEqual(ArticleIdentity.articleKey(url: URL(string: "https://example.com/a?page=2")!), plain,
                          "content-bearing query parameters stay part of the identity")
    }
}
