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
    /// Paces the reloads after the view's content process ends.
    @ObservationIgnored private var recovery = ContentProcessRecovery()

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

    /// The view stays on the page it loads (Follow's chapter preview): links, forms and back /
    /// forward to another address go nowhere, nothing opens a new window, and there are no swipes
    /// back. The page's own load, its redirects, its scripts' navigations, and links and forms
    /// back to its own address (a site's gate or challenge page) still run.
    let staysOnPage: Bool

    init(staysOnPage: Bool = false) {
        self.staysOnPage = staysOnPage
    }

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

    /// WebKit ended the view's content process (it crashed, or the system took its memory): the
    /// page shows blank until it loads again, so it reloads, paced by `ContentProcessRecovery`.
    /// The start page has nothing to reload; a page the user moved on to before the wait ended
    /// loads by itself.
    func contentProcessEnded() {
        guard hasPage, let delay = recovery.delayAfterEnd(at: Date()) else { return }
        Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let webView = self?.webView, !webView.isLoading else { return }
            webView.reload()
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

/// How a web view comes back after WebKit ends its content process. Left to itself WebKit reloads
/// once and leaves the page blank when the new process ends too, which a device short of memory
/// does several times in a row (a new process can die as it launches). This reloads at once, then
/// after a pause that grows, and gives up (the page stays blank until a reload or a navigation)
/// once the process has ended `delays.count` times within `window`, so a page that crashes its
/// process every time doesn't reload forever.
struct ContentProcessRecovery {
    static let delays: [TimeInterval] = [0, 2, 5]
    static let window: TimeInterval = 60

    private var ends: [Date] = []

    /// The process ended at `now`: how long to wait before reloading, or nil to leave the page.
    mutating func delayAfterEnd(at now: Date) -> TimeInterval? {
        ends = ends.filter { now.timeIntervalSince($0) < Self.window }
        guard ends.count < Self.delays.count else { return nil }
        let delay = Self.delays[ends.count]
        ends.append(now)
        return delay
    }
}
