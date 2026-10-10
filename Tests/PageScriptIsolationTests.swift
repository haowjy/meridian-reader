import WebKit
import XCTest
@testable import MeridianReader

/// Article HTML is untrusted. The off-screen parse view and the reader view run only the app's
/// own JavaScript (Readability, the reader bootstrap, highlight / scroll / jump calls); the
/// article's `<script>` tags, inline handlers and `javascript:` links never run.
/// Offline: broken images point at `reader.invalid` or nowhere, so their `onerror` would fire.
@MainActor
final class PageScriptIsolationTests: XCTestCase {
    private static let body = String(repeating: "The keeper climbs the tower at dusk, trims the wick, "
        + "polishes the lens and writes the weather in the log before the lamp is lit. ", count: 4)

    func testParseViewRunsReadabilityButNotPageScripts() async throws {
        let html = """
        <html><head><title>Keeping a Lighthouse Lamp</title></head><body><article>
        <h1>Keeping a Lighthouse Lamp</h1>
        <p>\(Self.body)</p>
        <p>\(Self.body)</p>
        <p>\(Self.body)</p>
        <img src="missing.png" onerror="document.querySelector('article').insertAdjacentHTML('beforeend',
          '<p>The broken image handler ran and added this sentence to the article.</p>')">
        <script>
          document.title = 'Page script ran';
          document.querySelector('article').insertAdjacentHTML('beforeend',
            '<p>The page script ran and added this sentence to the article.</p>');
        </script>
        </article></body></html>
        """
        let result = try await ReadabilityRunner.parse(html: html, baseURL: URL(string: "reader-test://lamp")!)
        XCTAssertEqual(result.title, "Keeping a Lighthouse Lamp")
        XCTAssertTrue(result.textContent.contains("trims the wick"), "Readability still parses")
        XCTAssertFalse(result.textContent.contains(" ran and added"), "page JavaScript ran: \(result.textContent)")
    }

    func testReaderViewRunsTheAppsScriptsButNotTheArticles() async throws {
        var taps: [Int] = []
        let coordinator = HTMLReadingWebView.Coordinator { taps.append($0) }
        let webView = HTMLReadingWebView.makeWebView(coordinator: coordinator)
        // Bridge messages count only in jump mode; on from the start, a post from the article
        // itself would show up as a tap.
        coordinator.setJumpMode(true)
        coordinator.load(html: """
        <h1>Keeping a Lighthouse Lamp</h1>
        <p>First paragraph.</p>
        <p>Second paragraph.</p>
        <img src="missing.png" onerror="document.body.dataset.ran = 'onerror';
          window.webkit.messageHandlers.readerBridge.postMessage({ index: 99 })">
        <script>
          document.body.dataset.ran = 'script';
          window.webkit.messageHandlers.readerBridge.postMessage({ index: 98 });
        </script>
        <div><a id="js-link" href="javascript:document.body.dataset.ran = 'link'">Link</a></div>
        """)
        try await waitUntil("page loaded and indexed") {
            guard !webView.isLoading else { return false }
            return (try await self.js(webView, "document.querySelectorAll('[data-reader-index]').length") as? Int) == 3
        }

        // The app's calls still run: highlight, scroll, and a jump-mode tap through readerBridge.
        coordinator.setActiveParagraph(2)
        coordinator.scroll(ReaderScrollRequest(index: 2, token: 1))
        _ = try await js(webView, "document.getElementById('js-link').click(); true")
        _ = try await js(webView, "document.querySelector('[data-reader-index=\"1\"]').click(); true")
        try await waitUntil("jump tap delivered") { !taps.isEmpty }
        try await waitUntil("highlight applied") {
            let active = "var el = document.querySelector('.reader-active'); el ? el.dataset.readerIndex : ''"
            return (try await self.js(webView, active) as? String) == "2"
        }
        try await Task.sleep(nanoseconds: 200_000_000) // let a `javascript:` navigation run, if any

        let ran = try await js(webView, "document.body.dataset.ran || ''") as? String
        XCTAssertEqual(ran, "", "article JavaScript ran")
        XCTAssertEqual(taps, [1], "only the app's tap handler posts to readerBridge")
    }

    private func js(_ webView: WKWebView, _ source: String) async throws -> Any? {
        try await webView.evaluateJavaScript(source)
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 10,
                           _ condition: () async throws -> Bool) async throws {
        let start = Date()
        while !(try await condition()) {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out: \(what)"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
