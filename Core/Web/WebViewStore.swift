import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class WebViewStore {
    weak var webView: WKWebView?
    var pageTitle: String?
    /// The page in the browser: set by `load` right away (the address field and buttons react
    /// before WebKit starts), then to what WebKit reports on each navigation event. nil on the
    /// start page: `about:` pages are never a page.
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

    var hasPage: Bool { currentURL != nil }

    func load(_ url: URL) {
        pendingURL = url
        currentURL = url
        isLoading = true
    }

    /// The start page: a blank document (so ‹ still goes back to the page), no page.
    func showStartPage() {
        pendingURL = URL(string: "about:blank")
        currentURL = nil
        pageTitle = nil
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func refresh() { webView?.reload() }

    func syncNavigationState() {
        guard let webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url.flatMap { $0.scheme == "about" ? nil : $0 }
        pageTitle = currentURL == nil ? nil : webView.title
    }

    /// The page as extraction reads it (`PageSnapshot`).
    func snapshotHTML() async throws -> String {
        guard let webView else {
            throw ExtractionError.engineFailed(message: "WebView isn’t ready yet.")
        }
        return try await PageSnapshot.html(of: webView)
    }
}
