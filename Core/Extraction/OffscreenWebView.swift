import Foundation
import ObjectiveC
import WebKit

/// The off-screen `WKWebView` extraction and the listen normalizer run in: never shown, with page
/// scripts off. HTML handed to it (a page snapshot taken after the page's own JavaScript ran, or a
/// book chapter) would otherwise run its `<script>` tags and inline handlers, fetch, and change the
/// DOM before it is read. The app's own `evaluateJavaScript` and `callAsyncJavaScript` calls still
/// run.
@MainActor
enum OffscreenWebView {
    static func make() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: config)
    }

    /// Loads `html` and returns once it has finished loading.
    static func load(_ webView: WKWebView, html: String, baseURL: URL?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let nav = NavigationWaiter(continuation: cont)
            webView.navigationDelegate = nav
            objc_setAssociatedObject(webView, &Associated.navKey, nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private enum Associated {
        static var navKey: UInt8 = 0
    }

    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false

        init(continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(ExtractionError.engineFailed(message: error.localizedDescription)))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(ExtractionError.engineFailed(message: error.localizedDescription)))
        }

        private func finish(_ outcome: Swift.Result<Void, Error>) {
            guard !finished else { return }
            finished = true
            continuation?.resume(with: outcome)
            continuation = nil
        }
    }
}
