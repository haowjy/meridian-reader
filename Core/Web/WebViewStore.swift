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
    /// WebKit's own history (`WKWebView.canGoBack` / `canGoForward`), kept current by `WebView`.
    var historyBack = false
    var historyForward = false
    /// The start page is up over the page the view still holds (‹ from the first page): › shows
    /// that page again. A load, or › itself, ends it.
    private(set) var startPageCoversPage = false
    /// 0…1 while a page loads (thin bar above the bottom chrome).
    var progress: Double = 0
    /// The page passes Readability's `isProbablyReaderable` (same gate extraction uses): the
    /// address-bar reader icon shows and ⋯ → Open in Reader is enabled.
    var isReaderable = false
    /// The page's own background (WebKit's `underPageBackgroundColor`, the page's computed
    /// background unless the page sets it): what the compact chrome's fade is drawn in over a page.
    var pageBackground: UIColor?
    @ObservationIgnored private var backgroundObservation: NSKeyValueObservation?
    /// A load asked for before the web view was made: it starts once the view attaches.
    @ObservationIgnored private var pendingURL: URL?
    /// Paces the reloads after the view's content process ends.
    @ObservationIgnored private var recovery = ContentProcessRecovery()
    /// The reload waiting after the content process ended.
    @ObservationIgnored private var recoveryReload: Task<Void, Never>?

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

    /// ‹: every page has somewhere to go back to, the page before it or, from the first, the start page.
    var canGoBack: Bool { hasPage }
    /// ›: the next page in history, or from the start page the page ‹ left.
    var canGoForward: Bool { startPageCoversPage || (hasPage && historyForward) }

    /// The view stays on the page it loads (Follow's chapter preview): links, forms and back /
    /// forward to another address go nowhere, nothing opens a new window, and there are no swipes
    /// back. The page's own load, its redirects, its scripts' navigations, and links and forms
    /// back to its own address (a site's gate or challenge page) still run.
    let staysOnPage: Bool

    init(staysOnPage: Bool = false) {
        self.staysOnPage = staysOnPage
    }

    /// A scroll to put the next finished load at (Listen's ‹ back to a page that reloads).
    @ObservationIgnored private(set) var pendingScrollY: Double?

    func restoreScroll(to y: Double?) { pendingScrollY = y }

    /// The finished load's saved scroll, once.
    func takePendingScroll() -> Double? {
        defer { pendingScrollY = nil }
        return pendingScrollY
    }

    func load(_ url: URL) {
        startPageCoversPage = false
        currentURL = url
        isLoading = true
        start(url)
    }

    /// The start page over the page on screen. The page stays in the view, stopped and its media
    /// paused, so › shows it again; a search or a site from the start page loads after it in history.
    func showStartPage() {
        guard hasPage else { return }
        webView?.stopLoading()
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        startPageCoversPage = true
        isLoading = false
        progress = 0
        currentURL = nil
        pageTitle = nil
    }

    /// The browser's web view is made (`WebView`): a load asked for before then starts.
    func attach(_ webView: WKWebView) {
        self.webView = webView
        backgroundObservation = webView.observe(\.underPageBackgroundColor, options: [.initial, .new]) { [weak self] view, _ in
            let color = view.underPageBackgroundColor
            MainActor.assumeIsolated { self?.pageBackground = color }
        }
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
    /// In the background it waits for the front first (a process started there is the first the
    /// system ends again; WebKit's own recovery waits too). The start page alone has nothing to
    /// reload (over a page it reloads that page, for ›), and a reload still waiting is dropped when
    /// the view has moved to another page or is loading one.
    func contentProcessEnded() {
        guard hasPage || startPageCoversPage, let webView else { return }
        let page = webView.backForwardList.currentItem
        recoveryReload?.cancel()
        recoveryReload = Task { [weak self, runState = AppRunState.shared] in
            if runState.phase == .background {
                for await _ in NotificationCenter.default.notifications(named: AppRunState.didChange, object: runState)
                    where runState.phase != .background { break }
            }
            guard !Task.isCancelled, let delay = self?.recovery.delayAfterEnd(at: Date()) else { return }
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let webView = self?.webView, !webView.isLoading,
                  webView.backForwardList.currentItem === page else { return }
            webView.reload()
        }
    }

    /// ‹: the page before this one, or from the first page the start page.
    func goBack() {
        guard hasPage else { return }
        if historyBack { webView?.goBack() } else { showStartPage() }
    }

    /// ›: from the start page the page it covers, else the next page in history.
    func goForward() {
        if startPageCoversPage {
            startPageCoversPage = false
            syncNavigationState()
        } else {
            webView?.goForward()
        }
    }

    func refresh() { webView?.reload() }
    func stopLoading() { webView?.stopLoading() }

    func syncNavigationState() {
        guard let webView else { return }
        historyBack = webView.canGoBack
        historyForward = webView.canGoForward
        // The covered page's own events (a late load, a script's pushState) leave the start page up.
        guard !startPageCoversPage else { return }
        currentURL = webView.url.flatMap { $0.scheme == "about" ? nil : $0 }
        pageTitle = currentURL == nil ? nil : webView.title
    }

    /// The page as extraction reads it (`PageSnapshot`).
    func snapshotHTML() async throws -> String {
        guard let webView else {
            throw ExtractionError.engineFailed(message: "The page isn’t ready yet. Try again in a moment.")
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
