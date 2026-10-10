import SwiftData
import SwiftUI

/// Favorites' pages and subfolders, live, for `content` (the start page's grid). A view of its own
/// because a query's folder id has to be known when the view is made.
struct FavoritesQuery<Content: View>: View {
    let folder: Folder
    @Query private var pages: [Page]
    private let content: ([Page], [Folder]) -> Content

    init(folder: Folder, @ViewBuilder content: @escaping ([Page], [Folder]) -> Content) {
        self.folder = folder
        _pages = Query(LibraryQueries.pages(inFolder: folder.id, sort: folder.pageSort))
        self.content = content
    }

    var body: some View { content(pages, LibraryStore.ordered(folder.children ?? [])) }
}
