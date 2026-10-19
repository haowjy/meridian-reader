import Foundation
import UIKit
import WebKit

/// Loads a web page out of sight and hands back what the browser would: the page as extraction
/// reads it (`PageSnapshot`), then its content, extracted as the browser extracts its own page
/// (`SingleWebPageSource`); or its links (`LinkPage`), for a story's table of contents. For pages
/// fetched without the browser, which it never touches. Follow's chapters and Downloads' links
/// come through here, one at a time, paced by `FetchQueue`.
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
/// - **The reply's status**: a page served with an HTTP error (a 404, a 429 asking to slow down, a
///   5xx) throws `FetchError.status`, with its `Retry-After`, rather than extracting the error page.
/// - **Time limits.** Loading, the snapshot and extraction each give up after `timeout`. WebKit's
///   processes can be suspended while the app is in the background, and their calls then don't
///   answer; a late answer is dropped.
///
/// `schemeHandlers`: URL schemes it serves itself (a Debug build's offline `reader-test://` pages).
/// One fetch at a time is the caller's rule.
@MainActor
final class URLPageFetcher {
    struct Snapshot: Equatable, Sendable {
        /// Where the page ended up, after redirects.
        var url: URL
        var html: String
    }

    enum Stage: String, Sendable {
        case load, snapshot, links, extract
    }

    /// Besides these, a load that fails or whose content process ends throws
    /// `NavigationWait.Failure`.
    enum FetchError: Error, Equatable {
        /// The app has no window to put the view in.
        case noWindow
        /// The stage didn't answer within the time limit.
        case timedOut(Stage)
        /// The site answered with an HTTP error; `retryAfter`: its `Retry-After`, in seconds.
        case status(Int, retryAfter: TimeInterval?)
        /// The page's links couldn't be read.
        case unreadableLinks
    }

    let extractor: any ArticleExtracting
    let timeout: TimeInterval
    private let schemeHandlers: [String: any WKURLSchemeHandler]

    init(extractor: any ArticleExtracting, timeout: TimeInterval = 30,
         schemeHandlers: [String: any WKURLSchemeHandler] = [:]) {
        self.extractor = extractor
        self.timeout = timeout
        self.schemeHandlers = schemeHandlers
    }

    /// The page at `url`, loaded, snapshotted and extracted.
    func content(of url: URL) async throws -> PageContent {
        try await content(of: snapshot(of: url))
    }

    /// The page at `url`, loaded in a hidden view and snapshotted.
    func snapshot(of url: URL) async throws -> Snapshot {
        try await loaded(url) { view in
            let html = try await self.within(.snapshot) { try await PageSnapshot.html(of: view) }
            return Snapshot(url: view.url ?? url, html: html)
        }
    }

    /// The page at `url`, loaded in a hidden view, and its links (a story's table of contents).
    func links(of url: URL) async throws -> LinkPage {
        try await loaded(url) { view in
            let json = try await self.within(.links) { try await view.evaluateJavaScript(Self.linksScript) as? String }
            guard let data = json?.data(using: .utf8),
                  let read = try? JSONDecoder().decode(ReadLinks.self, from: data) else { throw FetchError.unreadableLinks }
            return read.page(at: view.url ?? url)
        }
    }

    /// Loads `url` in a fresh hidden view and hands it to `read` once loaded, throwing the reply's
    /// HTTP error instead (`FetchError.status`). The view leaves the window when `read` is done.
    private func loaded<T>(_ url: URL, _ read: @escaping @MainActor (WKWebView) async throws -> T) async throws -> T {
        guard let window = Self.hostWindow() else { throw FetchError.noWindow }
        let view = Self.makeView(in: window, schemeHandlers: schemeHandlers)
        let navigation = NavigationWait()
        view.navigationDelegate = navigation
        defer {
            navigation.cancel()
            view.stopLoading()
            view.navigationDelegate = nil
            view.removeFromSuperview()
        }
        try await within(.load) { try await navigation.run { view.load(URLRequest(url: url)) } }
        if let reply = navigation.response, reply.statusCode >= 400 {
            let retryAfter = FetchPacing.retryAfter(reply.value(forHTTPHeaderField: "Retry-After"), now: Date())
            throw FetchError.status(reply.statusCode, retryAfter: retryAfter)
        }
        return try await read(view)
    }

    /// A snapshot's content, extracted as the browser extracts its page.
    func content(of snapshot: Snapshot) async throws -> PageContent {
        let page = SingleWebPageSource(url: snapshot.url, htmlSnapshot: snapshot.html, extractor: extractor)
        return try await within(.extract) { try await page.content(of: page.page) }
    }

    /// `operation`, within the time limit for `stage`.
    private func within<T>(_ stage: Stage, _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        try await NavigationWait.within(timeout, orThrow: FetchError.timedOut(stage), operation)
    }

    // MARK: - Links

    /// What `linksScript` returns.
    private struct ReadLinks: Decodable {
        struct Link: Decodable {
            var href: String
            var text: String
            var list: Int
        }

        var title: String?
        var heading: String?
        var author: String?
        var links: [Link]

        func page(at url: URL) -> LinkPage {
            LinkPage(url: url, title: title, heading: heading, author: author,
                     links: links.compactMap { link in
                         URL(string: link.href).map { LinkPage.Link(url: $0, text: link.text, list: link.list) }
                     })
        }
    }

    /// Every link with its text and the list it sits in (its nearest `ol`, `ul`, `table`, `nav` or
    /// `dl`, else its parent's parent, numbered in page order), the first heading, and the author
    /// (a story header's profile link, as Royal Road has, or a meta tag). The app's own script: it
    /// runs with the page's scripts off.
    private static let linksScript = """
    (() => {
      const squeeze = (t) => (t || "").replace(/\\s+/g, " ").trim();
      const lists = new Map();
      const listOf = (a) => {
        const el = a.closest("ol,ul,table,nav,dl") || (a.parentElement && a.parentElement.parentElement) || document.body;
        if (!lists.has(el)) lists.set(el, lists.size);
        return lists.get(el);
      };
      const links = [];
      for (const a of document.querySelectorAll("a[href]")) {
        if (!/^(https?|reader-test):/.test(a.href)) continue;
        links.push({ href: a.href, text: squeeze(a.innerText || a.textContent), list: listOf(a) });
      }
      const h1 = document.querySelector("h1");
      const meta = document.querySelector('meta[name="author"],meta[property="books:author"],meta[property="article:author"]');
      const profile = document.querySelector('.fic-header a[href*="/profile/"]');
      const author = profile ? squeeze(profile.textContent) : (meta ? squeeze(meta.content) : null);
      return JSON.stringify({ title: document.title || null, heading: h1 ? squeeze(h1.textContent) : null,
                              author: author || null, links });
    })()
    """

    // MARK: - The view

    /// The foreground scene's key window, else any of the app's windows.
    private static func hostWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func makeView(in window: UIWindow, schemeHandlers: [String: any WKURLSchemeHandler]) -> WKWebView {
        let config = WKWebViewConfiguration.appWebView(pageScripts: false, schemeHandlers: schemeHandlers)
        let size = window.bounds.size
        let frame = CGRect(x: -size.width - 100, y: 0, width: size.width, height: size.height)
        let view = WKWebView(frame: frame, configuration: config)
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        window.addSubview(view)
        return view
    }
}
