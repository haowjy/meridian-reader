import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class WebViewStore {
    weak var webView: WKWebView?
    var pageTitle: String?
    var currentURL: URL?
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    /// 0…1 while a page loads (thin bar above the bottom chrome).
    var progress: Double = 0
    /// The page passes Readability's `isProbablyReaderable` (same gate extraction uses): the
    /// address-bar reader icon shows and ⋯ → Open in Reader is enabled.
    var isReaderable = false
    /// Set by the address bar; consumed once by `WebView.updateUIView`.
    var pendingURL: URL?

    func load(_ url: URL) {
        pendingURL = url
        // Optimistic UI while load starts.
        currentURL = url
        isLoading = true
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func refresh() { webView?.reload() }

    func syncNavigationState() {
        guard let webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
        pageTitle = webView.title
    }

    func snapshotHTML() async throws -> String {
        guard let webView else {
            throw ExtractionError.engineFailed(message: "WebView isn’t ready yet.")
        }
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
