import UIKit
import WebKit
import XCTest
@testable import Reader

/// The reading page's real web view and coordinator, in a window of its own (WebKit lays out and
/// reports content size only for a view in a window), for tests that need WebKit's layout or DOM.
@MainActor
final class ReadingPageHarness {
    let coordinator: HTMLReadingWebView.Coordinator
    let webView: WKWebView
    private let window: UIWindow
    private(set) var taps: [Int] = []

    /// A window of `size`, the web view filling it below `viewportTop` (where a screen's header
    /// would end).
    init(size: CGSize = CGSize(width: 390, height: 600), viewportTop: CGFloat = 0) {
        var forward: (Int) -> Void = { _ in }
        coordinator = HTMLReadingWebView.Coordinator { forward($0) }
        webView = HTMLReadingWebView.makeWebView(coordinator: coordinator)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        webView.frame = CGRect(x: 0, y: viewportTop, width: size.width, height: size.height - viewportTop)
        window.addSubview(webView)
        window.isHidden = false
        forward = { [weak self] in self?.taps.append($0) }
    }

    func close() {
        webView.removeFromSuperview()
        window.isHidden = true
    }

    /// Moves the web view's top to `viewportTop` (a header above it growing or shrinking).
    func moveViewport(top viewportTop: CGFloat) {
        webView.frame = CGRect(x: 0, y: viewportTop, width: window.bounds.width, height: window.bounds.height - viewportTop)
    }

    var scrollView: UIScrollView { webView.scrollView }
    var offset: CGFloat { scrollView.contentOffset.y }
    /// The farthest the text scrolls down.
    var maxOffset: CGFloat {
        max(-scrollView.contentInset.top,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
    }

    /// Loads `html` and waits for the page to finish and number its `blocks` paragraphs.
    func load(_ html: String, blocks: Int, heading: ReaderHeading? = nil, opensAt: ReadingHandOver? = nil) async throws {
        coordinator.load(html: html, heading: heading, opensAt: opensAt)
        try await waitUntil("page loaded and indexed") {
            guard !self.webView.isLoading else { return false }
            return (try await self.js("document.querySelectorAll('[data-reader-index]').length") as? Int) == blocks
        }
    }

    /// Waits until the scroll view holds the page's whole layout: its content height is the
    /// document's. The page's DOM is complete when `load` returns, but WebKit hands its layout to
    /// the scroll view later, possibly in steps (a part of the page first), and the first one puts
    /// the offset back to the top. A test that scrolls, or reads `maxOffset`, before then acts on
    /// a page about to change under it; under CPU load that is most of the time.
    func waitUntilLaidOut(timeout: TimeInterval = 10) async throws {
        try await waitUntil("laid out", timeout: timeout) {
            let height = try await self.js("document.documentElement.scrollHeight") as? Double ?? 0
            return height > 0 && abs(self.scrollView.contentSize.height - CGFloat(height)) < 1
        }
    }

    /// The window y of the top of paragraph `index`'s first line.
    func windowY(ofParagraph index: Int) async throws -> CGFloat {
        let top = try await js("""
            (function(){ var p = document.querySelector('[data-reader-index="\(index)"]');
              return p.getBoundingClientRect().top - document.documentElement.getBoundingClientRect().top; })();
            """) as? Double
        return scrollView.convert(CGPoint(x: 0, y: CGFloat(top ?? .nan)), to: nil).y
    }

    func js(_ source: String) async throws -> Any? {
        try await webView.evaluateJavaScript(source)
    }

    /// `count` paragraphs of a few lines each.
    static func paragraphs(_ count: Int, from first: Int = 1) -> String {
        (first..<(first + count)).map {
            "<p>Paragraph \($0). The keeper climbs the tower at dusk, trims the wick, polishes the lens "
                + "and writes the weather in the log before the lamp is lit for the night.</p>"
        }.joined(separator: "\n")
    }

    func waitUntil(_ what: String, timeout: TimeInterval = 10,
                   _ condition: () async throws -> Bool) async throws {
        let start = Date()
        while !(try await condition()) {
            if Date().timeIntervalSince(start) > timeout { XCTFail("timed out: \(what)"); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
