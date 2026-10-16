import Foundation

extension URL {
    /// An http(s) page: what gets shared, recorded in history, or saved as an article.
    var isWeb: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    #if DEBUG
    /// The UI tests' offline pages' scheme (`reader-test://`, Debug builds). The app serves them
    /// itself (`TestPageSchemeHandler`, which App gives the web views); Core knows only the name.
    static let testPageScheme = "reader-test"
    #endif

    /// The web, plus (Debug builds) the UI tests' offline `reader-test://` pages: what the browser
    /// checks for reader mode and lets you bookmark.
    var isWebOrTestPage: Bool {
        #if DEBUG
        if scheme?.lowercased() == Self.testPageScheme { return true }
        #endif
        return isWeb
    }

    /// Same page: the same canonical URL (`ArticleIdentity`), the rule that gives a page its key.
    /// The fragment, tracking parameters (`utm_*`, …), a trailing slash and the scheme's and
    /// host's case don't count; the path's and the query's case do.
    func isSamePage(as other: URL) -> Bool {
        ArticleIdentity.canonicalURLString(from: self) == ArticleIdentity.canonicalURLString(from: other)
    }
}
