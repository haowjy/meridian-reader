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
    /// A load asked for before the web view was made: it starts once the view attaches.
    @ObservationIgnored private var pendingURL: URL?

    /// A book (`.epub`) the page linked to, downloading into `BookImportFiles` instead of showing.
    enum BookDownload {
        case started(name: String)
        /// The file, ready to import.
        case finished(URL)
        case failed(name: String)
    }

    /// Told about each book download (the browser hands a finished one to the import sheet).
    @ObservationIgnored var onBookDownload: ((BookDownload) -> Void)?

    var hasPage: Bool { currentURL != nil }

    func load(_ url: URL) {
        currentURL = url
        isLoading = true
        start(url)
    }

    /// The start page: a blank document (so ‹ still goes back to the page), no page.
    func showStartPage() {
        currentURL = nil
        pageTitle = nil
        if let blank = URL(string: "about:blank") { start(blank) }
    }

    /// The browser's web view is made (`WebView`): a load asked for before then starts.
    func attach(_ webView: WKWebView) {
        self.webView = webView
        if let pending = pendingURL {
            pendingURL = nil
            webView.load(URLRequest(url: pending))
        }
        syncNavigationState()
    }

    private func start(_ url: URL) {
        if let webView {
            webView.load(URLRequest(url: url))
        } else {
            pendingURL = url
        }
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
