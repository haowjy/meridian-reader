import SwiftUI

/// The Favorites folder on the start page, as Safari shows its Favorites: a grid of its pages
/// (icon tile and title), then its subfolders as folder tiles. Long-press a page tile to rename
/// it or take it out of Favorites.
struct FavoritesGrid: View {
    let pages: [Page]
    let folders: [Folder]
    var onOpen: (Page) -> Void
    var onOpenFolder: (Folder) -> Void
    var onRemove: (Page) -> Void
    var onRename: (Page, String) -> Void

    /// A tile's icon.
    static let tileSize: CGFloat = 60

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var renaming: Page?
    @State private var renameText = ""

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs, alignment: .top), count: 4),
                  spacing: Spacing.m) {
            ForEach(pages, id: \.listenKey) { page in
                Button { onOpen(page) } label: {
                    tile(title: page.title) { FavoriteIcon(page: page, size: Self.tileSize) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
                .accessibilityIdentifier("favoriteTile")
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") {
                        renameText = page.title
                        renaming = page
                    }
                    Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) { onRemove(page) }
                }
            }
            ForEach(folders, id: \.id) { folder in
                Button { onOpenFolder(folder) } label: {
                    tile(title: folder.displayName) { folderIcon(folder) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(folder.displayName)
                .accessibilityHint("Folder")
                .accessibilityIdentifier("favoriteFolderTile")
            }
        }
        .alert("Rename Favorite", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { onRename(renaming, renameText) }
                renaming = nil
            }
        }
    }

    private func tile<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: Spacing.xs) {
            icon()
            Text(title)
                .typeStyle(.caption)
                .foregroundStyle(Palette.ink)
                // At accessibility sizes a second line would only hold a word broken mid-way; one
                // truncated line reads better.
                .lineLimit(typeSize.isAccessibilitySize ? 1 : 2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
    }

    private func folderIcon(_ folder: Folder) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.tileSize * 0.22, style: .continuous)
                .fill(Palette.chrome)
            if let cover = folder.coverImage {
                ArtworkTile(image: cover, letter: folder.displayName, size: Self.tileSize * 0.5, isCover: true)
            } else {
                Image(systemName: folder.rowSymbol)
                    .font(.title2)
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .accessibilityHidden(true)
    }
}
