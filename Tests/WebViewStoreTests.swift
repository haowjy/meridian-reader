import WebKit
import XCTest
@testable import MeridianReader

/// The browser's loads: asked for before its web view exists, one starts when the view attaches;
/// after that each starts at once, outside any view update.
@MainActor
final class WebViewStoreTests: XCTestCase {
    func testALoadBeforeTheViewStartsWhenItAttaches() {
        let store = WebViewStore()
        let page = URL(string: "https://example.com/a")!
        store.load(page)
        XCTAssertEqual(store.currentURL, page, "the address shows at once")

        let view = RecordingWebView()
        store.attach(view)
        XCTAssertEqual(view.loaded, [page])
    }

    func testALoadOnceAttachedStartsAtOnce() {
        let store = WebViewStore()
        let view = RecordingWebView()
        store.attach(view)
        XCTAssertEqual(view.loaded, [], "nothing was waiting")

        let page = URL(string: "https://example.com/b")!
        store.load(page)
        XCTAssertEqual(view.loaded, [page])
        store.showStartPage()
        XCTAssertEqual(view.loaded.last, URL(string: "about:blank"))
        XCTAssertNil(store.currentURL)
    }
}

/// Records what it is asked to load, loading nothing.
private final class RecordingWebView: WKWebView {
    var loaded: [URL] = []

    init() { super.init(frame: .zero, configuration: WKWebViewConfiguration()) }
    required init?(coder: NSCoder) { fatalError() }

    override func load(_ request: URLRequest) -> WKNavigation? {
        if let url = request.url { loaded.append(url) }
        return nil
    }
}
