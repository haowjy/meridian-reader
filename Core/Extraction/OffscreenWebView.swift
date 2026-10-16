import Foundation
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

    /// Loads `html` and returns once it has finished loading. Throws when the load fails, its
    /// content process ends, `timeout` passes first (`ExtractionError.engineFailed`; WebKit's
    /// processes can be suspended while the app is in the background, and then don't answer), or
    /// the calling task is cancelled.
    static func load(_ webView: WKWebView, html: String, baseURL: URL?, timeout: TimeInterval = 30) async throws {
        let navigation = NavigationWait()
        webView.navigationDelegate = navigation
        defer {
            navigation.cancel()
            webView.navigationDelegate = nil
        }
        let late = ExtractionError.engineFailed(message: String(localized: "The page took too long to load."))
        try await NavigationWait.within(timeout, orThrow: late) {
            try await navigation.run { webView.loadHTMLString(html, baseURL: baseURL) }
        }
    }
}
