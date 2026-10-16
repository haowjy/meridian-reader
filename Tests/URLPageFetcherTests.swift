import UIKit
import WebKit
import XCTest
@testable import MeridianReader

/// The hidden fetcher reads a page as the browser does: its snapshot drops the short text the
/// page's CSS hides, and the page extracts exactly as the browser's own copy of it does.
@MainActor
final class URLPageFetcherTests: XCTestCase {
    private let page = TestPageSchemeHandler.hiddenSpanPage
    private let hiddenLines = TestPageSchemeHandler.hiddenLines

    func testTheSnapshotDropsCSSHiddenTextAndExtractsAsTheBrowserDoes() async throws {
        let fetcher = URLPageFetcher(timeout: 20)
        let snapshot = try await fetcher.snapshot(of: page)
        XCTAssertEqual(snapshot.url, page)
        XCTAssertEqual(snapshot.title, "Hidden span page")
        for line in hiddenLines {
            XCTAssertFalse(snapshot.html.contains(line), "the snapshot drops the CSS-hidden line: \(line)")
        }
        XCTAssertTrue(snapshot.html.contains("Paragraph 5."), "and keeps the visible text")
        XCTAssertFalse(hostedFetchViewRemains(), "the hidden view leaves the window")

        // The page as served holds both lines, and extraction alone keeps them (Readability looks
        // only at inline styles): only the snapshot keeps them out of the text.
        let served = try XCTUnwrap(TestPageSchemeHandler.fetchPage("hidden-span"))
        let unfiltered = try await fetcher.content(of: .init(url: page, title: snapshot.title, html: served))
        for line in hiddenLines {
            XCTAssertTrue(unfiltered.plainText.contains(line), "control: without the snapshot, extraction keeps \(line)")
        }

        let content = try await fetcher.content(of: snapshot)
        for line in hiddenLines {
            XCTAssertFalse(content.bodyHTML.contains(line), line)
            XCTAssertFalse(content.document.paragraphs.contains { $0.contains(line) }, line)
        }
        XCTAssertEqual(content.title, "Hidden span page")
        let paragraphs = content.document.paragraphs.filter { $0.hasPrefix("Paragraph ") }
        XCTAssertEqual(paragraphs.map { String($0.prefix(12)) }, (1...5).map { "Paragraph \($0)." },
                       "each visible paragraph is a listen block, in order")

        let browser = try await browserExtraction(of: page)
        XCTAssertEqual(snapshot.html, browser.html, "the browser's snapshot of the page")
        XCTAssertEqual(content.ref, browser.content.ref)
        XCTAssertEqual(content.extracted, browser.content.extracted, "title, site, reading HTML, text, excerpt")
        XCTAssertEqual(content.document, browser.content.document, "the listen blocks")
        XCTAssertEqual(content.languageCode, browser.content.languageCode)
    }

    func testALoadThatNeverFinishesGivesUpAtTheTimeLimit() async throws {
        let fetcher = URLPageFetcher(timeout: 1)
        let started = Date()
        do {
            _ = try await fetcher.snapshot(of: TestPageSchemeHandler.stallingPage)
            XCTFail("the page never answers")
        } catch {
            XCTAssertEqual(error as? URLPageFetcher.FetchError, .timedOut(.load))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(hostedFetchViewRemains(), "the hidden view leaves the window")
    }

    // MARK: - The browser's path

    /// The page through the browser's path: a web view configured as the browser's (page scripts
    /// on, `WebView`) in a window, then `WebViewStore.snapshotHTML` and `SingleWebPageSource` with
    /// the app's extractor, as `PageArticleService` extracts the browser's page.
    private func browserExtraction(of url: URL) async throws -> (html: String, content: PageContent) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.setURLSchemeHandler(TestPageSchemeHandler(), forURLScheme: TestPageSchemeHandler.scheme)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let webView = WKWebView(frame: window.bounds, configuration: config)
        window.addSubview(webView)
        window.isHidden = false
        defer {
            webView.removeFromSuperview()
            window.isHidden = true
        }
        let navigation = NavigationEnd()
        webView.navigationDelegate = navigation
        try await navigation.load(url, in: webView)
        // WebKit can report the title a moment after `didFinish` (seen after another test's
        // stalled load); the browser's address field and title follow it on a later event.
        for _ in 0..<40 where webView.title?.isEmpty != false { try await Task.sleep(for: .milliseconds(50)) }

        let store = WebViewStore()
        store.webView = webView
        store.syncNavigationState()
        let html = try await store.snapshotHTML()
        let source = SingleWebPageSource(url: try XCTUnwrap(store.currentURL), pageTitle: store.pageTitle,
                                         htmlSnapshot: html, extractor: ReadabilityArticleExtractor())
        return (html, try await source.content(of: source.page))
    }

    /// A hidden fetch view still in one of the app's windows (left of its window's edge).
    private func hostedFetchViewRemains() -> Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .flatMap(\.subviews).contains { $0 is WKWebView && $0.frame.maxX < 0 }
    }

    @MainActor
    private final class NavigationEnd: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func load(_ url: URL, in webView: WKWebView) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
