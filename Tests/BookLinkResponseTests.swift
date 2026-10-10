import XCTest
@testable import Reader

/// Which main-frame responses the browser downloads as a book (`WebView.Coordinator.isBook`):
/// one served as an EPUB, or one named `.epub` that isn't a web page. Everything else shows.
final class BookLinkResponseTests: XCTestCase {
    private func response(_ url: String, mimeType: String?, disposition: String? = nil) -> URLResponse {
        guard let disposition else {
            return URLResponse(url: URL(string: url)!, mimeType: mimeType, expectedContentLength: 0, textEncodingName: nil)
        }
        var headers = ["Content-Disposition": disposition]
        if let mimeType { headers["Content-Type"] = mimeType }
        return HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    func testServedAsAnEPUBIsABookWhateverItsName() {
        XCTAssertTrue(WebView.Coordinator.isBook(response("https://example.com/download?id=7", mimeType: "application/epub+zip")))
        XCTAssertTrue(WebView.Coordinator.isBook(response("https://example.com/get", mimeType: "Application/EPUB+zip")),
                      "the type is matched without case")
        XCTAssertTrue(WebView.Coordinator.isBook(response("https://example.com/get", mimeType: "application/epub+zip",
                                                          disposition: "attachment; filename=\"lantern.bin\"")),
                      "even named otherwise by the server")
    }

    func testNamedEPUBAndNotAWebPageIsABook() {
        XCTAssertTrue(WebView.Coordinator.isBook(response("https://example.com/books/lantern.epub", mimeType: "application/octet-stream")))
        XCTAssertTrue(WebView.Coordinator.isBook(response("https://example.com/download?id=7", mimeType: "application/octet-stream",
                                                          disposition: "attachment; filename=\"The Lantern Keeper.epub\"")),
                      "named by its Content-Disposition")
        XCTAssertTrue(WebView.Coordinator.isBook(response("https://example.com/books/LANTERN.EPUB", mimeType: nil)))
    }

    func testAWebPageNamedEPUBShows() {
        XCTAssertFalse(WebView.Coordinator.isBook(response("https://example.com/books/lantern.epub", mimeType: "text/html")))
        XCTAssertFalse(WebView.Coordinator.isBook(response("https://example.com/books/lantern.epub", mimeType: "application/xhtml+xml")))
    }

    func testOrdinaryResponsesShow() {
        XCTAssertFalse(WebView.Coordinator.isBook(response("https://example.com/article", mimeType: "text/html")))
        XCTAssertFalse(WebView.Coordinator.isBook(response("https://example.com/paper.pdf", mimeType: "application/pdf")))
        XCTAssertFalse(WebView.Coordinator.isBook(response("https://example.com/archive.zip", mimeType: "application/zip")))
    }
}
