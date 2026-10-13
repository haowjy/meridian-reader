import SwiftData
import SwiftUI

/// Favorites' pages and subfolders, live, for `content` (the start page's grid). A view of its own
/// because a query's folder id has to be known when the view is made.
struct FavoritesQuery<Content: View>: View {
    @Query private var pages: [Page]
    @Query private var folders: [Folder]
    private let content: ([Page], [Folder]) -> Content

    init(@ViewBuilder content: @escaping ([Page], [Folder]) -> Content) {
        _pages = Query(LibraryQueries.favoritePages)
        self.content = content
    }

    var body: some View { content(pages.filter(\.isLive), LibraryStore.ordered(folders.filter { $0.isLive && $0.isFavorite })) }
}
