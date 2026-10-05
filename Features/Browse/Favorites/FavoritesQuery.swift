import SwiftData
import SwiftUI

/// Favorites' pages, live, for `content` (the start page's grid). A view of its own because a
/// query's folder id has to be known when the view is made.
struct FavoritesQuery<Content: View>: View {
    @Query private var pages: [Page]
    private let content: ([Page]) -> Content

    init(folderID: UUID, @ViewBuilder content: @escaping ([Page]) -> Content) {
        _pages = Query(LibraryQueries.pages(inFolder: folderID))
        self.content = content
    }

    var body: some View { content(pages) }
}
