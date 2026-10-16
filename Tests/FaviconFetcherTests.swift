import UIKit
import WebKit
import XCTest
@testable import MeridianReader

/// Icons are images, and the live page's icon is the page's own.
@MainActor
final class FaviconFetcherTests: XCTestCase {
    private let url = URL(string: "https://example.com/favicon.ico")!

    private func answer(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private var png: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }

    /// A missing favicon answered with a 200 HTML page isn't an icon.
    func testHTMLIsNoIcon() {
        let html = Data("<!DOCTYPE html><html><head><title>Not found</title></head><body>Sorry</body></html>".utf8)
        XCTAssertNil(FaviconFetcher.icon(html, response: answer(200)))
    }

    func testAnImageIsAnIcon() {
        XCTAssertEqual(FaviconFetcher.icon(png, response: answer(200)), png)
        XCTAssertNil(FaviconFetcher.icon(png, response: answer(404)), "an error page")
    }

    /// The browser moved on to another page (a link followed while 🎧 extracted): its document
    /// isn't asked for this page's icon.
    func testTheLiveDocumentCountsOnlyWhileItShowsThePage() {
        let page = URL(string: "https://example.com/story")!
        let web = ShowingWebView(showing: URL(string: "https://example.com/story?utm_source=feed#top")!)
        XCTAssertIdentical(FaviconFetcher.document(in: web, showing: page), web)
        web.showing = URL(string: "https://example.org/next")!
        XCTAssertNil(FaviconFetcher.document(in: web, showing: page))
        web.showing = nil
        XCTAssertNil(FaviconFetcher.document(in: web, showing: page))
        XCTAssertNil(FaviconFetcher.document(in: nil, showing: page))
    }
}

/// A web view that says it shows `showing`, loading nothing.
private final class ShowingWebView: WKWebView {
    var showing: URL?

    init(showing: URL?) {
        self.showing = showing
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) { fatalError() }

    override var url: URL? { showing }
}
