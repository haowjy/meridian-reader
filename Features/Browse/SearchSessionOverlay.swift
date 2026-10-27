import SwiftData
import SwiftUI

/// The address search session's layer over the page (Brave's search): opaque paper down to the
/// keyboard, and at its top, under the safe area, one rounded card of rows. Untouched, the card is
/// Recent Searches; typing, it is `Search "typed"` (runs the search), then what matches in history and
/// saved pages, then the search engine's live suggestions (`SearchSuggestions`). A row's ↖︎ puts its
/// text in the field without searching. Scrolling the card's layer drags the keyboard down with the
/// finger (the system's interactive dismissal); with nothing to list, a swipe down lowers it. Either
/// way the session stays.
struct SearchSessionOverlay: View {
    let session: SearchSession
    let recentSearches: [String]
    let visits: [RecentVisit]
    var isDictating: Bool
    var onSubmit: (String) -> Void
    var onClearRecentSearches: () -> Void

    /// The saved pages, for suggestions: read only while the layer is up.
    @Query(LibraryQueries.savedInLibrary) private var articles: [Article]
    /// The engine's suggestions for what is typed. They stay until the next answer replaces them
    /// (no flicker between keystrokes), and go at once when there is nothing to ask about.
    @State private var live: [String] = []
    @Environment(\.searchSuggestionProvider) private var provider
    @AppStorage(SearchSuggestions.storageKey) private var suggestionsOn = true

    private var typed: String { session.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var showsRecentSearches: Bool {
        session.isUntouched && !recentSearches.isEmpty && !isDictating
    }

    private var suggestions: [AddressSuggestion] {
        guard !showsRecentSearches else { return [] }
        return AddressSuggestions.build(query: session.text, visits: visits.prefix(RecentVisit.maxEntries),
                                        articles: articles.lazy.map(SavedArticleSuggestion.init), google: live)
    }

    var body: some View {
        let suggestions = suggestions
        let hasTyped = !session.isUntouched && !typed.isEmpty
        ZStack(alignment: .top) {
            // (An identifier on a container would replace the rows' own, so it sits on the paper only.)
            Palette.paper
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("addressEditBackdrop")

            if showsRecentSearches || hasTyped {
                ScrollView {
                    Group {
                        if showsRecentSearches {
                            recentSearchesCard
                        } else {
                            suggestionsCard(suggestions)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .padding(.horizontal, ChromeMetrics.margin)
                    .padding(.top, Spacing.s)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                // Nothing to list yet: the empty layer still takes the pull-down.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .lowersKeyboardOnPullDown(session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: session.text) {
            let rows = await SearchSuggestions.rows(typed: session.text, enabled: suggestionsOn && !session.isUntouched,
                                                    provider: provider)
            if !Task.isCancelled { live = rows }
        }
    }

    private var recentSearchesCard: some View {
        VStack(spacing: 0) {
            SectionHeader(title: Verbs.recentSearches, size: .page, actionTitle: Verbs.clearAll,
                          actionIdentifier: "recentSearchesClear", action: onClearRecentSearches)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xs)

            ForEach(recentSearches, id: \.self) { term in
                SymbolRowSeparator(leadingInset: Spacing.m)
                SuggestionRow(title: term, subtitle: nil, openLabel: term, identifier: "recentSearch.\(term)",
                              onOpen: { onSubmit(term) }, onFill: { session.fill(term) }) {
                    Image(systemName: Icons.search).foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        .background(Palette.chrome)
    }

    private func suggestionsCard(_ rows: [AddressSuggestion]) -> some View {
        VStack(spacing: 0) {
            // First: what is typed, as a search (or, for an address, opened).
            SuggestionRow(title: typedRowTitle, subtitle: nil, openLabel: typedRowTitle, identifier: "searchTyped",
                          onOpen: { onSubmit(session.text) }, onFill: nil) {
                Image(systemName: BrowseURLParser.isSearch(typed) ? Icons.search : Icons.browser)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(rows) { row in
                SymbolRowSeparator(leadingInset: Spacing.m)
                SuggestionRow(title: row.title, subtitle: row.subtitle, identifier: "searchSuggestion.\(row.title)",
                              onOpen: { onSubmit(row.query) }, onFill: { session.fill(row.query) }) {
                    switch row.kind {
                    case .recent, .saved:
                        ArtworkTile(image: row.faviconData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                                    letter: ArticleRowTitle.artworkLetter(title: row.title, source: row.host, address: row.query),
                                    size: Glyph.rowLeading)
                    case .google:
                        Image(systemName: Icons.search).foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
        }
        .background(Palette.chrome)
    }

    private var typedRowTitle: String {
        BrowseURLParser.isSearch(typed) ? String(localized: "Search “\(typed)”") : String(localized: "Go to “\(typed)”")
    }
}

/// One row of the search layer (a `SymbolRow`): tap opens it; the ↖︎ arrow (Safari's fill
/// control) puts it in the field without opening.
private struct SuggestionRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    /// Accessibility label of the open button, when its icon would otherwise be read too.
    var openLabel: String? = nil
    var identifier: String? = nil
    let onOpen: () -> Void
    /// nil: no ↖︎ (the typed text is already in the field).
    let onFill: (() -> Void)?
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 0) {
            if let openLabel {
                openButton.accessibilityLabel(openLabel)
            } else {
                openButton
            }

            if let onFill {
                Button(action: onFill) {
                    Image(systemName: Icons.fillField)
                        .rowSymbol()
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: BottomChrome.minTapTarget, height: BottomChrome.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Insert into search field")
                .accessibilityIdentifier(identifier.map { "\($0).fill" } ?? "")
                .padding(.trailing, Spacing.xxs)
            }
        }
    }

    private var openButton: some View {
        Button(action: onOpen) {
            SymbolRow(title, subtitle: subtitle.map { DetailPart($0) }, leading: leading) { EmptyView() }
                .padding(.leading, Spacing.m)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

extension EnvironmentValues {
    /// Where the address field's live suggestions come from; a Debug launch (`-uiTesting`) swaps it
    /// so results don't depend on the network.
    @Entry var searchSuggestionProvider = SearchSuggestionProvider.live
}
