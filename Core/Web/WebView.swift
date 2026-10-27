import SwiftUI
import WebKit

extension EnvironmentValues {
    /// URL schemes the browser's web view serves itself, by scheme: none in a normal launch; the UI
    /// tests' offline pages when a Debug launch asks for them (App sets it).
    @Entry var webViewSchemeHandlers: [String: any WKURLSchemeHandler] = [:]
}

/// A web view that reports the chrome's footprint as its bottom obscured inset: that footprint above
/// the safe area, plus the safe area itself (the page runs under the home indicator). Re-applied when the
/// safe area arrives or changes, which is after the first `updateUIView`.
final class ObscuredWebView: WKWebView {
    var obscuredBottom: CGFloat = 0 { didSet { if obscuredBottom != oldValue { applyObscuredInset() } } }

    private func applyObscuredInset() {
        guard #available(iOS 26.0, *) else { return }
        // Zero stays zero: nothing covers the page (regular width, no chrome).
        // The window's, not the view's: SwiftUI lets the page run under the home indicator, and the view's
        // own safe area can read 0 there.
        let home = max(safeAreaInsets.bottom, window?.safeAreaInsets.bottom ?? 0)
        let bottom = obscuredBottom > 0 ? obscuredBottom + home : 0
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
        if obscuredContentInsets != insets { obscuredContentInsets = insets }
        // What `lvh` (the large viewport) and `svh` (the small one) measure: the capsule's footprint and the
        // expanded one's, as in Safari with its bar folded and unfolded (`dvh` follows the obscured inset). Both
        // zero where nothing covers the page. (`100vh` itself stays the whole frame: WebKit ties it to neither.)
        let folded = obscuredBottom > 0 ? UIEdgeInsets(top: 0, left: 0, bottom: ChromeMetrics.capsuleFootprint + home, right: 0) : .zero
        let expanded = obscuredBottom > 0 ? UIEdgeInsets(top: 0, left: 0, bottom: ChromeMetrics.footprint + home, right: 0) : .zero
        if minimumViewportInset != folded || maximumViewportInset != expanded {
            setMinimumViewportInset(folded, maximumViewportInset: expanded)
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        applyObscuredInset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyObscuredInset()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyObscuredInset()
    }
}

struct WebView: UIViewRepresentable {
    var store: WebViewStore
    /// Room the page keeps clear at the bottom, for chrome floating over it: the page scrolls
    /// through it, so its last line can rise above the chrome.
    var bottomInset: CGFloat = 0
    /// What the chrome covers at the bottom of the page *right now*, above the home indicator: the page's own
    /// layout viewport ends above it, so a `position:fixed;bottom:0` banner, a sticky footer and `100vh`
    /// all sit above the chrome (iOS 26's `obscuredContentInsets`; before it the page runs under the chrome,
    /// as `bottomInset` alone leaves it). It follows the chrome's fold in one step, not every frame.
    var obscuredBottom: CGFloat = 0
    /// The user's scroll position (0 at the top of the page), while they drag or the page coasts.
    var onScroll: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration.appWebView(pageScripts: true,
                                                       schemeHandlers: context.environment.webViewSchemeHandlers)

        let webView = ObscuredWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = !store.staysOnPage
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground

        context.coordinator.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.store = store
        context.coordinator.onScroll = onScroll
        (webView as? ObscuredWebView)?.obscuredBottom = obscuredBottom
        if webView.scrollView.contentInset.bottom != bottomInset {
            webView.scrollView.contentInset.bottom = bottomInset
            webView.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        }
        if store.webView !== webView {
            context.coordinator.attach(webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var store: WebViewStore
        /// `WebViewStore.staysOnPage`, read where WebKit asks.
        private let staysOnPage: Bool
        private var observations: [NSKeyValueObservation] = []
        var onScroll: ((CGFloat) -> Void)?
        @MainActor init(store: WebViewStore) {
            self.store = store
            staysOnPage = store.staysOnPage
        }

        @MainActor
        func attach(_ webView: WKWebView) {
            store.attach(webView)
            // Delegate callbacks miss same-document history (#fragments, pushState): observe the
            // web view directly so ‹ / › enable exactly when WebKit can go back / forward.
            observations = [
                webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.canGoForward = wv.canGoForward }
                },
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor in self?.store.progress = wv.estimatedProgress }
                },
                // Only the user's own scrolling moves the chrome, not a page loading or restoring.
                webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                    guard scroll.isDragging || scroll.isDecelerating else { return }
                    let inset = scroll.adjustedContentInset
                    let farthest = scroll.contentSize.height + inset.bottom + inset.top - scroll.bounds.height
                    let offset = min(scroll.contentOffset.y + inset.top, max(farthest, 0))
                    Task { @MainActor in self?.onScroll?(offset) }
                },
                // Same-document URL changes (pushState sites) never hit `didFinish`: recheck.
                webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                    Task { @MainActor in
                        guard let self, !wv.isLoading else { return }
                        self.checkReaderable(wv, after: 0.8)
                    }
                },
            ]
        }

        private var readerableGeneration = 0

        /// Runs Readability's `isProbablyReaderable` in an isolated content world (page scripts
        /// can't see or break it). Once now-ish and once later, for content that renders late.
        @MainActor
        func checkReaderable(_ webView: WKWebView, after delay: TimeInterval = 0) {
            readerableGeneration += 1
            let generation = readerableGeneration
            let url = webView.url
            guard let js = ReaderScripts.readerableCheck, let url,
                  url.isWebOrTestPage
            else {
                store.isReaderable = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                guard let self, let webView, generation == self.readerableGeneration, webView.url == url else { return }
                webView.evaluateJavaScript(js, in: nil, in: .defaultClient) { result in
                    guard generation == self.readerableGeneration, webView.url == url else { return }
                    if case .success(let value) = result {
                        self.store.isReaderable = (value as? Bool) ?? false
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                store.isLoading = true
                readerableGeneration += 1
                store.isReaderable = false
                store.syncNavigationState()
            }
        }

        /// Handled here, WebKit doesn't reload the page itself (`WebViewStore.contentProcessEnded`).
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in store.contentProcessEnded() }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in store.syncNavigationState() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                store.isLoading = false
                store.syncNavigationState()
                checkReaderable(webView)
                // Late-rendered articles (client-side apps): look once more.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
                    guard let self, let webView, !self.store.isReaderable else { return }
                    self.checkReaderable(webView)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                store.isLoading = false
                store.syncNavigationState()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                store.isLoading = false
                store.syncNavigationState()
            }
        }

        // MARK: - Staying on the page

        /// A view that stays on its page (`WebViewStore.staysOnPage`) cancels a link, a form, or
        /// back / forward that would take it to another page. One that stays on the page's own
        /// address (`#notes`, `?page=2`, a site's gate or challenge form posting back to it) goes:
        /// WebKit can't tell a script's form submit from a tap's.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard staysOnPage, navigationAction.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow) }
            switch navigationAction.navigationType {
            case .linkActivated, .formSubmitted, .formResubmitted, .backForward:
                let stays = navigationAction.request.url.flatMap { url in webView.url.map { Self.sameAddress(url, $0) } }
                decisionHandler(stays == true ? .allow : .cancel)
            default:
                decisionHandler(.allow)
            }
        }

        /// The same scheme, host and path: the query and the fragment may differ.
        static func sameAddress(_ a: URL, _ b: URL) -> Bool {
            a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
                && a.path == b.path
        }

        // MARK: - Books

        /// A book (an EPUB) the page links to is downloaded, not shown.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            decisionHandler(navigationResponse.isForMainFrame && Self.isBook(navigationResponse.response) ? .download : .allow)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        /// Served as an EPUB, or named like one and not a web page.
        static func isBook(_ response: URLResponse) -> Bool {
            let type = response.mimeType?.lowercased()
            if type == "application/epub+zip" { return true }
            guard type != "text/html", type != "application/xhtml+xml" else { return false }
            return (response.suggestedFilename ?? response.url?.lastPathComponent ?? "").lowercased().hasSuffix(".epub")
        }

        /// Where each download in flight goes, and its name.
        private var bookDownloads: [ObjectIdentifier: (file: URL, name: String)] = [:]

        private func tell(_ event: WebViewStore.BookDownload) {
            Task { @MainActor in store.onBookDownload?(event) }
        }

        // MARK: - New windows

        /// A link that opens a new window (`target=_blank`, `window.open`): there are no tabs, so it
        /// loads here (nowhere in a view that stays on its page).
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if !staysOnPage, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

extension WebView.Coordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        guard let file = try? BookImportFiles.standard.newFile(named: suggestedFilename) else {
            tell(.failed(name: suggestedFilename))
            return completionHandler(nil)
        }
        bookDownloads[ObjectIdentifier(download)] = (file, file.lastPathComponent)
        tell(.started(name: file.lastPathComponent))
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let book = bookDownloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        tell(.finished(book.file))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let book = bookDownloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        BookImportFiles.standard.discard(book.file)
        tell(.failed(name: book.name))
    }
}
