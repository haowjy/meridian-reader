import WebKit

extension WKWebViewConfiguration {
    /// Block Ads for every configuration `appWebView` makes, set once at launch before the first web
    /// view (`AppComposition.makeContentBlocker`). Unset, views load unblocked.
    @MainActor static var appContentBlocker: ContentBlocker?

    /// The configuration every web view in the app starts from (the browser and Follow's preview,
    /// the hidden fetcher, extraction, the Reader's text): the default website data store, so they
    /// share the browser's cookies; media plays only after a tap; Block Ads (`appContentBlocker`).
    /// `pageScripts`: whether the page's own JavaScript runs (the app's scripts run either way).
    /// `schemeHandlers`: URL schemes the view serves itself.
    @MainActor
    static func appWebView(pageScripts: Bool,
                           schemeHandlers: [String: any WKURLSchemeHandler] = [:]) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.allowsContentJavaScript = pageScripts
        for (scheme, handler) in schemeHandlers { config.setURLSchemeHandler(handler, forURLScheme: scheme) }
        appContentBlocker?.register(config.userContentController)
        return config
    }
}
