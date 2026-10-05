import SwiftUI

/// Safari-Favorites-style grid of Favorites' pages: icon tile + title. Long-press → Rename /
/// Delete.
struct BookmarkGrid: View {
    let bookmarks: [Page]
    var onOpen: (Page) -> Void
    var onDelete: (Page) -> Void
    var onRename: (Page, String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var renaming: Page?
    @State private var renameText = ""

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs, alignment: .top), count: 4),
                  spacing: Spacing.m) {
            ForEach(bookmarks, id: \.listenKey) { bookmark in
                Button { onOpen(bookmark) } label: {
                    VStack(spacing: Spacing.xs) {
                        BookmarkIcon(bookmark: bookmark, size: 60)
                        Text(bookmark.title)
                            .typeStyle(.caption)
                            .foregroundStyle(Palette.ink)
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
