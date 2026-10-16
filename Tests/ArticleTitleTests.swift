import XCTest
@testable import MeridianReader

/// An extracted title loses a trailing site name, and nothing else.
final class ArticleTitleTests: XCTestCase {
    func testDropsTheSiteNameFromTheHost() {
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix("Speech synthesis - Wikipedia", siteName: nil,
                                                      host: "en.wikipedia.org"), "Speech synthesis")
    }

    func testDropsTheSiteNameGiven() {
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix("Tide Tables | The Harbor Gazette", siteName: "The Harbor Gazette",
                                                      host: "news.example.com"), "Tide Tables")
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix("Tide Tables — Example", siteName: nil, host: "www.example.com"),
                       "Tide Tables")
    }

    func testKeepsATitleWhoseLastPartIsNotTheSite() {
        let title = "Bonds - A Short Guide"
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix(title, siteName: "Example", host: "example.com"), title)
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix("Example", siteName: "Example", host: "example.com"), "Example")
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix(" - Example", siteName: nil, host: "example.com"), " - Example")
    }

    func testTheLastSeparatorDecides() {
        XCTAssertEqual(ArticleTitle.withoutSiteSuffix("Coupons - Basics | Example", siteName: nil, host: "example.com"),
                       "Coupons - Basics")
    }
}

/// The reading page keeps its own look: an extracted page's stylesheets are left out.
final class ReadingPageStylesTests: XCTestCase {
    func testStylesheetsAreLeftOut() {
        let html = """
        <!DOCTYPE html><html><head><style>body{font:-apple-system-body;color:#111}</style>
        <link rel="stylesheet" href="a.css"></head><body><h1>Title</h1><p>One</p></body></html>
        """
        let out = ReadingStyle.withoutPageStyles(html)
        XCTAssertFalse(out.contains("apple-system-body"), out)
        XCTAssertFalse(out.contains("a.css"), out)
        XCTAssertTrue(out.contains("<p>One</p>"), out)
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: out), ListenHTMLBlocks.leafTexts(fromHTML: html),
                       "the same listen blocks")
    }
}
