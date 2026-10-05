import Foundation
import WebKit

/// The page a web view shows, as the HTML extraction reads: without the short text its CSS hides
/// (`ReaderVisibleSnapshot.js`), else the whole document. The browser (`WebViewStore`) and the
/// hidden fetcher (`URLPageFetcher`) both take it, so a page extracts the same either way.
@MainActor
enum PageSnapshot {
    static func html(of webView: WKWebView) async throws -> String {
        let plain = "document.documentElement ? document.documentElement.outerHTML : document.body.outerHTML"
        // Prefer a snapshot without short invisible text (anti-copy lines hidden by site CSS,
        // which the saved copy can't hide because it drops the site's stylesheets).
        var result: Any?
        if let visibleJS = ReaderScripts.visibleSnapshot {
            result = try? await webView.evaluateJavaScript(visibleJS + "\n__readerVisibleSnapshot();")
        }
        if (result as? String)?.isEmpty ?? true {
            result = try await webView.evaluateJavaScript(plain)
        }
        guard let html = result as? String, !html.isEmpty else {
            throw ExtractionError.emptyContent
        }
        return html
    }
}
