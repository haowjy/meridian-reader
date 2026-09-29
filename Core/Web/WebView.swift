import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    var store: WebViewStore
    var initialURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if ProcessInfo.processInfo.arguments.contains("-browseTestPages") {
            config.setURLSchemeHandler(TestPageSchemeHandler(), forURLScheme: TestPageSchemeHandler.scheme)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground

        context.coordinator.attach(webView)
        if let initialURL {
            webView.load(URLRequest(url: initialURL))
        }
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
            guard let js = ReaderScripts.readerableCheck,
                  let scheme = url?.scheme, scheme == "http" || scheme == "https" || scheme == TestPageSchemeHandler.scheme
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

/// UI tests only (`-browseTestPages`): serves two tiny offline pages at `reader-test://pages/one`
/// and `/two` (real navigations, so they get real back/forward history).
final class TestPageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "reader-test"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let isTwo = url.path.hasSuffix("two")
        let title = isTwo ? "Second page" : "First page"
        let link = isTwo ? "" : "<p><a href=\"reader-test://pages/two\" style=\"display:block;padding:24px;background:#ddd\">Next page</a></p>"
        // Page two is an article (passes isProbablyReaderable); page one is not.
        let sentence = "This offline test article has a long paragraph so Readability counts it as real reading content. "
        let article = isTwo ? (1...5).map { _ in "<p>" + String(repeating: sentence, count: 4) + "</p>" }.joined() : ""
        let html = """
        <html><head><meta name="viewport" content="width=device-width"><title>\(title)</title></head>
        <body style="font: 20px -apple-system; padding: 24px"><h1>\(title)</h1>\(link)\(article)</body></html>
        """
        let data = Data(html.utf8)
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
