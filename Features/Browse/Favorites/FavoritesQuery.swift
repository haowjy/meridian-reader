import SwiftData
import SwiftUI

/// The starred pages and folders, live, for `content` (the start page's grid), by
/// `LibraryQueries`' favorite lists.
struct FavoritesQuery<Content: View>: View {
    @Query private var articles: [Article]
    @Query private var folders: [Folder]
    private let content: ([Article], [Folder]) -> Content

    init(@ViewBuilder content: @escaping ([Article], [Folder]) -> Content) {
        _articles = Query(LibraryQueries.favoriteArticles)
        _folders = Query(LibraryQueries.favoriteFolders)
        self.content = content
    }

    var body: some View { content(articles.filter(\.isLive), LibraryStore.ordered(folders.filter(\.isLive))) }
}
