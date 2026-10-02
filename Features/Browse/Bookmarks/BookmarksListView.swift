import SwiftUI

/// All bookmarks: tap to open, swipe or Edit to delete / reorder.
struct BookmarksListView: View {
    @Bindable var store: BookmarkStore
    var onOpen: (SiteBookmark) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks", systemImage: "star",
                                           description: Text("Open a site, then ⋯ → Bookmark."))
                } else {
                    List {
                        ForEach(store.bookmarks) { bookmark in
                            Button { onOpen(bookmark) } label: {
                                HStack(spacing: 12) {
                                    BookmarkIcon(bookmark: bookmark, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bookmark.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(bookmark.host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { store.remove(atOffsets: $0) }
                        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.bookmarks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
        }
        .accessibilityIdentifier("bookmarksList")
    }
}
