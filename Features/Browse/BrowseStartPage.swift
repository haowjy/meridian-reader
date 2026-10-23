import SwiftUI

/// The browser's start page (no page loaded), Safari-style: starred pages that have their own
/// http(s) address (Show All opens the Library's Favorites tab), then Recent Searches. Folders
/// are not shown here — only in Library › Favorites.
struct BrowseStartPage: View {
    let favorites: [Article]
    let recentSearches: [String]
    var onOpenFavorite: (Article) -> Void
    var onShowFavorites: () -> Void
    /// A page tile's long press: the page's menu (`ArticleMenu`).
    var pageMenu: (Article) -> AnyView
    var onSearch: (String) -> Void
    var onClearSearches: () -> Void

    /// Two rows of four tiles; Show All opens Library › Favorites.
    static let favoriteLimit = 8

    private var hasFavorites: Bool { !favorites.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if hasFavorites {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: Verbs.favorites, size: .page,
                                      actionTitle: Verbs.showAll,
                                      actionNavigates: true, actionIdentifier: "startFavoritesShowAll",
                                      action: onShowFavorites)
                        FavoritesGrid(articles: Array(favorites.prefix(Self.favoriteLimit)),
                                      onOpen: onOpenFavorite, articleMenu: pageMenu)
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

    /// The search layer's Recent Searches as a card: the same header, action and rows
    /// (`SymbolRow`, 🔍), a tap searching again.
    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader(title: Verbs.recentSearches, size: .page, actionTitle: Verbs.clearAll,
                          actionIdentifier: "startSearchesClear", action: onClearSearches)
            VStack(spacing: 0) {
                ForEach(recentSearches, id: \.self) { term in
                    Button { onSearch(term) } label: {
                        SymbolRow(term, symbol: Icons.search)
                            .padding(.horizontal, Spacing.m)
                    }
                    .buttonStyle(.plain)
                    if term != recentSearches.last {
                        SymbolRowSeparator(leadingInset: Spacing.m)
                    }
                }
            }
            .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startRecentSearches")
    }
}
