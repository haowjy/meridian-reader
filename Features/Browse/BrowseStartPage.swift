import SwiftUI

/// The browser's start page (no page loaded), Safari-style: Frequently Visited (the sites with the
/// most pages in History, starter sites until visits fill a row; Show All opens History), then
/// Recent Searches.
struct BrowseStartPage: View {
    let sites: [FrequentSite]
    let recentSearches: [String]
    var onOpenSite: (FrequentSite) -> Void
    var onShowHistory: () -> Void
    var onSearch: (String) -> Void
    var onClearSearches: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(title: Verbs.frequentlyVisited, size: .page,
                                  actionTitle: Verbs.showAll,
                                  actionNavigates: true, actionIdentifier: "startFrequentShowAll",
                                  action: onShowHistory)
                    FrequentlyVisitedGrid(sites: sites, onOpen: onOpenSite)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("startFrequentlyVisited")

                if !recentSearches.isEmpty {
                    recentSearchesSection
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
