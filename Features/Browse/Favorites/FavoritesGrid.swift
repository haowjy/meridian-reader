import SwiftUI

/// The start page's starred pages and folders, as Safari shows its Favorites: a grid of pages
/// (icon tile and title), then folders as folder tiles. A tile's long press is its item's menu,
/// the same as everywhere that page or folder shows (`ArticleMenu`, `FolderMenu`).
struct FavoritesGrid: View {
    let articles: [Article]
    let folders: [Folder]
    var onOpen: (Article) -> Void
    var onOpenFolder: (Folder) -> Void
    var articleMenu: (Article) -> AnyView
    var folderMenu: (Folder, _ onTurnOffDownload: @escaping () -> Void) -> AnyView

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs, alignment: .top), count: 4),
                  spacing: Spacing.m) {
            ForEach(articles, id: \.listenKey) { article in
                Button { onOpen(article) } label: {
                    tile(title: article.lineOne) {
                        ArtworkTile(image: article.favoriteIcon, letter: article.artworkLetter, size: Glyph.favoriteTile)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(article.lineOne)
                .accessibilityIdentifier("favoriteTile")
                .contextMenu { articleMenu(article) }
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
                ArtworkTile(image: cover, letter: folder.name, size: Glyph.favoriteCover, isCover: true)
            } else {
                Image(systemName: folder.rowSymbol)
                    .tileSymbol()
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: Glyph.favoriteTile, height: Glyph.favoriteTile)
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
        .accessibilityHint(String(localized: "Opens it in the Library"))
        .accessibilityIdentifier("favoriteFolderTile")
        .contextMenu { menu(folder) { turningOff = folder } }
        .turnOffDownloadQuestion($turningOff)
    }
}

private extension Article {
    /// Its site icon for a Favorites tile, unless it is too small to fill one (a 16 px favicon
    /// looks smeared there; the letter tile reads better).
    var favoriteIcon: Image? {
        guard FaviconFetcher.isTileSized(artworkData), let data = artworkData,
              let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
    }
}
