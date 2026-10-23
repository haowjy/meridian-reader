import SwiftData
import SwiftUI

/// Starred pages with an http(s) address, live, for the browser start page's Favorites strip.
/// Library Favorites (folders and every starred page) is unchanged; this query is Browse-only.
struct FavoritesQuery<Content: View>: View {
    @Query private var articles: [Article]
    private let content: ([Article]) -> Content

    init(@ViewBuilder content: @escaping ([Article]) -> Content) {
        _articles = Query(LibraryQueries.favoriteArticles)
        self.content = content
    }

    var body: some View {
        content(articles.filter(\.isLive).filter(\.hasBrowseURL))
    }
}

extension Article {
    /// An address the browser start page can open (http or https only).
    var hasBrowseURL: Bool {
        guard let url, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
