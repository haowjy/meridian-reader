import SwiftData
import SwiftUI

/// The starred pages and folders, live, for `content` (the start page's grid), by
/// `LibraryQueries`' favorite lists.
struct FavoritesQuery<Content: View>: View {
    @Query private var pages: [Page]
    @Query private var folders: [Folder]
    private let content: ([Page], [Folder]) -> Content

    init(@ViewBuilder content: @escaping ([Page], [Folder]) -> Content) {
        _pages = Query(LibraryQueries.favoritePages)
        _folders = Query(LibraryQueries.favoriteFolders)
        self.content = content
    }

    var body: some View { content(pages.filter(\.isLive), LibraryStore.ordered(folders.filter(\.isLive))) }
}
