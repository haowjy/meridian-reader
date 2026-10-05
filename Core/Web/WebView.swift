import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    var store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        #if DEBUG
        if LaunchOptions.current.servesTestPages {
            config.setURLSchemeHandler(TestPageSchemeHandler(), forURLScheme: TestPageSchemeHandler.scheme)
        }
        #endif

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground

        context.coordinator.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.store = store
        if store.webView !== webView {
            context.coordinator.attach(webView)
        }
        // Only load when the address bar (or chips) explicitly requested a URL.
        if let pending = store.pendingURL {
            store.pendingURL = nil
            webView.load(URLRequest(url: pending))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var store: WebViewStore
        private var observations: [NSKeyValueObservation] = []
        init(store: WebViewStore) { self.store = store }

        @MainActor
        func attach(_ webView: WKWebView) {
            store.webView = webView
            store.syncNavigationState()
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

#if DEBUG
/// UI tests only (`LaunchOptions.servesTestPages`): offline pages at `reader-test://pages/…` (real
/// navigations, so they get real back/forward history):
/// - `one`: not an article (no 📄 / 🎧), with links to the others;
/// - `two` ("Second page") and `three` ("Third page"): articles (pass `isProbablyReaderable`);
/// - `thin` ("Thin page"): readable by that check, but its article text is invisible, so the
///   saved copy (which drops short invisible text) has almost nothing to listen to;
/// - `book-N`: chapter N of the demo book (`DemoBook`, `-seedDemoBook`).
final class TestPageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "reader-test"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let html = Self.page(url.lastPathComponent)
        let data = Data(html.utf8)
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func page(_ name: String) -> String {
        let sentence = "This offline test article has a long paragraph so Readability counts it as real reading content. "
        let title: String
        var body: String
        if let chapter = DemoBook.testPage(name) {
            return document(title: chapter.title, body: chapter.body)
        }
        switch name {
        case "two":
            title = "Second page"
            body = (1...5).map { _ in "<p>" + String(repeating: sentence, count: 4) + "</p>" }.joined()
        case "three":
            title = "Third page"
            let other = "A different offline article, about harbors and the boats that come and go with the tide. "
            body = (1...5).map { _ in "<p>" + String(repeating: other, count: 4) + "</p>" }.joined()
        case "thin":
            title = "Thin page"
            // Each paragraph is long enough for the readable check (which ignores opacity) and
            // short enough for the snapshot to drop as hidden text.
            let hidden = "Hidden text that only the readability check can see, never the listener, on this page."
            body = (1...5).map { _ in "<p style=\"opacity:0\">" + hidden + " " + hidden + "</p>" }.joined()
                + "<p>Only a line here.</p>"
        default:
            title = "First page"
            let link = "style=\"display:block;padding:24px;background:#ddd;margin-bottom:8px\""
            body = "<p><a href=\"reader-test://pages/two\" \(link)>Next page</a></p>"
                + "<p><a href=\"reader-test://pages/three\" \(link)>Third page</a></p>"
                + "<p><a href=\"reader-test://pages/thin\" \(link)>Thin page</a></p>"
        }
        return document(title: title, body: body)
    }

    private static func document(title: String, body: String) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width"><title>\(title)</title></head>
        <body style="font: 20px -apple-system; padding: 24px"><h1>\(title)</h1>\(body)</body></html>
        """
    }
}
#endif
