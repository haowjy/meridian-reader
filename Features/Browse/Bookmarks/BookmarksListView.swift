import SwiftData
import SwiftUI

/// All of Favorites' pages: tap to open, swipe or Edit to delete / reorder.
struct BookmarksListView: View {
    let library: LibraryStore
    var onOpen: (Page) -> Void

    @Query private var favorites: [Page]

    init(library: LibraryStore, onOpen: @escaping (Page) -> Void) {
        self.library = library
        self.onOpen = onOpen
        _favorites = Query(LibraryQueries.pages(inFolder: library.favorites().id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView("No bookmarks", systemImage: "star",
                                           description: Text("Open a site, then ⋯ → Bookmark."))
                } else {
                    List {
                        ForEach(favorites, id: \.listenKey) { bookmark in
                            Button { onOpen(bookmark) } label: {
                                HStack(spacing: 12) {
                                    BookmarkIcon(bookmark: bookmark, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bookmark.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(bookmark.byline)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for page in offsets.map({ favorites[$0] }) { library.removeFavorite(page) }
                        }
                        .onMove { source, destination in
                            let moving = source.map { favorites[$0] }
                            let before = destination < favorites.count ? favorites[destination] : nil
                            library.reorder(moving, in: library.favorites(), before: before)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !favorites.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
        }
        .accessibilityIdentifier("bookmarksList")
    }
}
