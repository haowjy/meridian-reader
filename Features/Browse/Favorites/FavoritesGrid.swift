import SwiftUI

/// The start page's starred pages that have an http(s) address, as Safari shows Favorites: a
/// grid of icon tiles. A tile's long press is the page's menu (`ArticleMenu`). Tap opens the
/// address in Browse — never the Library Reader.
struct FavoritesGrid: View {
    let articles: [Article]
    var onOpen: (Article) -> Void
    var articleMenu: (Article) -> AnyView

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
                .accessibilityHint(String(localized: "Opens in Browse"))
                .accessibilityIdentifier("favoriteTile")
                .contextMenu { articleMenu(article) }
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
