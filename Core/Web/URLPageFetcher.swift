import Foundation
import UIKit
import WebKit

/// Loads a web page out of sight and hands back what the browser would: the page as extraction
/// reads it (`PageSnapshot`), then its content, extracted as the browser extracts its own page
/// (`SingleWebPageSource`). For pages fetched without the browser, which it never touches.
///
/// - **A real view, out of sight.** Each fetch gets a fresh `WKWebView` the size of the app's
///   window, placed off its left side: the page lays out at the width the browser shows it, in a
///   view WebKit counts as on screen (it treats one in no window as hidden). The test page reads
///   the same in the Simulator from a zero-size or windowless view; the size and the window are
///   for real pages, laid out by their CSS, and for the device. The view takes no touches, is left
///   out of the accessibility tree and leaves the window when the fetch ends.
/// - **The browser's cookies**: the default website data store, so a page you're signed in to in
///   the browser loads signed in here.
/// - **Page scripts off**, as for extraction: the snapshot is the page as served, laid out with
///   its CSS. The app's own scripts still run.
/// - **Time limits.** Loading, the snapshot and extraction each give up after `timeout`. WebKit's
///   processes can be suspended while the app is in the background, and their calls then don't
///   answer; a late answer is dropped.
///
/// Debug builds serve the offline `reader-test://` pages (`TestPageSchemeHandler`) to it.
/// One fetch at a time is the caller's rule.
@MainActor
final class URLPageFetcher {
    struct Snapshot: Equatable, Sendable {
        /// Where the page ended up, after redirects.
        var url: URL
        /// The document's title, as the browser reads it (`WKWebView.title`).
        var title: String?
        var html: String
    }

    enum Stage: String, Sendable {
        case load, snapshot, extract
    }

    /// Besides these, a load that fails or whose content process ends throws
    /// `NavigationWait.Failure`.
    enum FetchError: Error, Equatable {
        /// The app has no window to put the view in.
        case noWindow
        /// The stage didn't answer within the time limit.
        case timedOut(Stage)
    }

    let extractor: any ArticleExtracting
    let timeout: TimeInterval

    init(extractor: any ArticleExtracting = ReadabilityArticleExtractor(), timeout: TimeInterval = 30) {
        self.extractor = extractor
        self.timeout = timeout
    }

    /// The page at `url`, loaded, snapshotted and extracted.
    func content(of url: URL) async throws -> PageContent {
        try await content(of: snapshot(of: url))
    }

    /// The page at `url`, loaded in a hidden view and snapshotted.
    func snapshot(of url: URL) async throws -> Snapshot {
        guard let window = Self.hostWindow() else { throw FetchError.noWindow }
        let view = Self.makeView(in: window)
        let navigation = NavigationWait()
        view.navigationDelegate = navigation
        defer {
            navigation.cancel()
            view.stopLoading()
            view.navigationDelegate = nil
            view.removeFromSuperview()
        }
        try await within(.load) { try await navigation.run { view.load(URLRequest(url: url)) } }
        let html = try await within(.snapshot) { try await PageSnapshot.html(of: view) }
        return Snapshot(url: view.url ?? url, title: view.title, html: html)
    }

    /// A snapshot's content, extracted as the browser extracts its page.
    func content(of snapshot: Snapshot) async throws -> PageContent {
        let page = SingleWebPageSource(url: snapshot.url, pageTitle: snapshot.title, htmlSnapshot: snapshot.html,
                                       extractor: extractor)
        return try await within(.extract) { try await page.content(of: page.page) }
    }

    /// `operation`, within the time limit for `stage`.
    private func within<T>(_ stage: Stage, _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        try await NavigationWait.within(timeout, orThrow: FetchError.timedOut(stage), operation)
    }

    // MARK: - The view

    /// The foreground scene's key window, else any of the app's windows.
    private static func hostWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func makeView(in window: UIWindow) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        #if DEBUG
        config.setURLSchemeHandler(TestPageSchemeHandler(), forURLScheme: TestPageSchemeHandler.scheme)
        #endif
        let size = window.bounds.size
        let frame = CGRect(x: -size.width - 100, y: 0, width: size.width, height: size.height)
        let view = WKWebView(frame: frame, configuration: config)
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        window.addSubview(view)
        return view
    }
}
