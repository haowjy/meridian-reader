import Foundation

extension URL {
    /// An http(s) page: what gets shared, recorded in history, or saved as an article.
    var isWeb: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The web, plus (Debug builds) the UI tests' offline `reader-test://` pages: what the browser
    /// checks for reader mode and lets you bookmark.
    var isWebOrTestPage: Bool {
        #if DEBUG
        if scheme?.lowercased() == TestPageSchemeHandler.scheme { return true }
        #endif
        return isWeb
    }

    /// Same page, ignoring the fragment, a trailing slash and letter case.
    func isSamePage(as other: URL) -> Bool {
        Self.pageKey(self) == Self.pageKey(other)
    }

    private static func pageKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        var key = components?.string ?? url.absoluteString
        if key.hasSuffix("/") { key.removeLast() }
        return key.lowercased()
    }
}
