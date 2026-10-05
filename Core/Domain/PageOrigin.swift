import Foundation

/// Where a page's text comes from: a web address, or a chapter's place in an imported book.
enum PageOrigin: Hashable, Sendable {
    /// A web page: its address as visited, and the canonical form the library knows it by
    /// (`ArticleIdentity.canonicalURLString`; one page per canonical URL).
    case web(URL, canonicalURL: String)
    /// A chapter of an imported book, at its place in the book ("href#fragment", `Page.locator`),
    /// or any other page with no web address.
    case book(locator: String)

    static func web(_ url: URL) -> PageOrigin {
        .web(url, canonicalURL: ArticleIdentity.canonicalURLString(from: url))
    }

    /// Web pages: the address as visited.
    var url: URL? {
        if case .web(let url, _) = self { return url }
        return nil
    }

    var urlString: String? { url?.absoluteString }

    /// Web pages: what the library and 🎧 match the page by.
    var canonicalURL: String? {
        if case .web(_, let canonical) = self { return canonical }
        return nil
    }
}
