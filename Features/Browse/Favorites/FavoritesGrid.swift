import SwiftUI

/// The start page's starred pages and folders, as Safari shows its Favorites: a grid of pages
/// (icon tile and title), then folders as folder tiles. A tile's long press is its item's menu,
/// the same as everywhere that page or folder shows (`PageMenu`, `FolderMenu`).
struct FavoritesGrid: View {
    let pages: [Page]
    let folders: [Folder]
    var onOpen: (Page) -> Void
    var onOpenFolder: (Folder) -> Void
    var pageMenu: (Page) -> AnyView
    var folderMenu: (Folder, _ onTurnOffDownload: @escaping () -> Void) -> AnyView

    /// A tile's icon.
    static let tileSize: CGFloat = 60

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs, alignment: .top), count: 4),
                  spacing: Spacing.m) {
            ForEach(pages, id: \.listenKey) { page in
                Button { onOpen(page) } label: {
                    tile(title: page.lineOne) {
                        ArtworkTile(image: page.favoriteIcon, letter: page.artworkLetter, size: Self.tileSize)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.lineOne)
                .accessibilityIdentifier("favoriteTile")
                .contextMenu { pageMenu(page) }
            }
            ForEach(folders, id: \.id) { folder in
                FolderTile(folder: folder, onOpen: onOpenFolder, menu: folderMenu) { title, icon in
                    tile(title: title) { icon }
                }
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

    static func folderIcon(_ folder: Folder) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.chrome)
            if let cover = folder.coverImage {
                ArtworkTile(image: cover, letter: folder.name, size: Self.tileSize * 0.5, isCover: true)
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

/// A folder's tile: its own view, so *Turn Off Download*, asked from its menu, shows by it.
private struct FolderTile<Tile: View>: View {
    let folder: Folder
    let onOpen: (Folder) -> Void
    let menu: (Folder, @escaping () -> Void) -> AnyView
    let tile: (String, AnyView) -> Tile

    @State private var turningOff: Folder?

    var body: some View {
        Button { onOpen(folder) } label: {
            tile(folder.name, AnyView(FavoritesGrid.folderIcon(folder)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(folder.name)
        .accessibilityHint("Folder")
        .accessibilityIdentifier("favoriteFolderTile")
        .contextMenu { menu(folder) { turningOff = folder } }
        .turnOffDownloadQuestion($turningOff)
    }
}

private extension Page {
    /// Its site icon for a Favorites tile, unless it is too small to fill one (a 16 px favicon
    /// looks smeared there; the letter tile reads better).
    var favoriteIcon: Image? {
        guard FaviconFetcher.isTileSized(artworkData), let data = artworkData,
              let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
    }
}
