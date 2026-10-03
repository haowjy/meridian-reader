import SwiftUI

/// Safari-Favorites-style grid: icon tile + title. Long-press → Rename / Delete.
struct BookmarkGrid: View {
    let bookmarks: [SiteBookmark]
    var onOpen: (SiteBookmark) -> Void
    var onDelete: (SiteBookmark) -> Void
    var onRename: (SiteBookmark, String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var renaming: SiteBookmark?
    @State private var renameText = ""

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4),
                  spacing: 14) {
            ForEach(bookmarks) { bookmark in
                Button { onOpen(bookmark) } label: {
                    VStack(spacing: 6) {
                        BookmarkIcon(bookmark: bookmark, size: 60)
                        Text(bookmark.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            // At accessibility sizes a second line would only hold a word broken
                            // mid-way; one truncated line reads better.
                            .lineLimit(typeSize.isAccessibilitySize ? 1 : 2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmark.title)
                .accessibilityIdentifier("bookmarkTile")
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") {
                        renameText = bookmark.title
                        renaming = bookmark
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(bookmark) }
                }
            }
        }
        .alert("Rename Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { onRename(renaming, renameText) }
                renaming = nil
            }
        }
    }
}
