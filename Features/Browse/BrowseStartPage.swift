import SwiftUI

/// The browser's start page (no page loaded), Safari-style: the Favorites folder (a grid of its
/// pages, then its subfolders as folder tiles; Show All opens the Favorites sheet), then Recent
/// Searches.
struct BrowseStartPage: View {
    let favorites: [Page]
    let favoriteFolders: [Folder]
    let recentSearches: [String]
    var onOpenFavorite: (Page) -> Void
    var onOpenFavoriteFolder: (Folder) -> Void
    var onShowFavorites: () -> Void
    var onRemoveFavorite: (Page) -> Void
    var onRenameFavorite: (Page, String) -> Void
    var onSearch: (String) -> Void
    var onClearSearches: () -> Void

    /// Two rows of four tiles; Show All opens the whole folder.
    static let favoriteLimit = 8
    /// Width of a recent search's clock glyph.
    private static let searchIconWidth: CGFloat = 20

    private var hasFavorites: Bool { !favorites.isEmpty || !favoriteFolders.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if hasFavorites {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: String(localized: "Favorites"), size: .page,
                                      actionTitle: String(localized: "Show All"),
                                      actionNavigates: true, actionIdentifier: "startFavoritesShowAll",
                                      action: onShowFavorites)
                        FavoritesGrid(pages: Array(favorites.prefix(Self.favoriteLimit)),
                                      folders: Array(favoriteFolders.prefix(max(0, Self.favoriteLimit - favorites.count))),
                                      onOpen: onOpenFavorite, onOpenFolder: onOpenFavoriteFolder,
                                      onRemove: onRemoveFavorite, onRename: onRenameFavorite)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("startFavorites")
                }

                if !recentSearches.isEmpty {
                    recentSearchesSection
                }

                if !hasFavorites && recentSearches.isEmpty {
                    Text("Search or enter an address below. Pages you add to Favorites show up here.")
                        .typeStyle(.row)
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.xl)
                }
            }
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Palette.paper)
        .accessibilityIdentifier("browseStartPage")
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Searches")
                    .typeStyle(.heading)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear", action: onClearSearches)
                    .typeStyle(.row)
                    .accessibilityIdentifier("startSearchesClear")
            }
            VStack(spacing: 0) {
                ForEach(recentSearches, id: \.self) { term in
                    Button { onSearch(term) } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Palette.secondaryInk)
                                .frame(width: Self.searchIconWidth)
                            Text(term)
                                .typeStyle(.row)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if term != recentSearches.last {
                        Divider().padding(.leading, Spacing.s + Self.searchIconWidth + Spacing.s)
                    }
                }
            }
            .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startRecentSearches")
    }
}
