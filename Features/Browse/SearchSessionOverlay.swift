import SwiftData
import SwiftUI

/// The address search session's full-bleed layer over the page (Safari): Recent Searches while
/// the field is untouched, otherwise suggestions (history, saved articles, Google). Scrolling the
/// list drags the keyboard down with the finger (the system's interactive dismissal); with
/// nothing to list, a swipe down lowers it. Either way the session stays.
struct SearchSessionOverlay: View {
    let session: SearchSession
    let recentSearches: [String]
    let visits: [RecentVisit]
    var isDictating: Bool
    var onSubmit: (String) -> Void
    var onClearRecentSearches: () -> Void

    /// The saved pages, for suggestions: read only while the layer is up.
    @Query(LibraryQueries.savedInLibrary) private var articles: [Page]
    @State private var google: [String] = []
    @Environment(\.fetchesSearchSuggestions) private var fetchesGoogle

    private static let googleDebounce: Duration = .milliseconds(280)

    private var showsRecentSearches: Bool {
        session.isUntouched && !recentSearches.isEmpty && !isDictating
    }

    private var suggestions: [AddressSuggestion] {
        guard !showsRecentSearches else { return [] }
        return AddressSuggestions.build(query: session.text, visits: visits.prefix(RecentVisit.maxEntries),
                                        articles: articles.lazy.map(SavedPageSuggestion.init), google: google)
    }

    var body: some View {
        let suggestions = suggestions
        ZStack(alignment: .top) {
            Palette.paper
                .ignoresSafeArea(edges: .bottom)

            if showsRecentSearches || !suggestions.isEmpty {
                ScrollView {
                    Group {
                        if showsRecentSearches {
                            recentSearchesList
                        } else {
                            suggestionsList(suggestions)
                        }
                    }
                    .padding(.top, Spacing.xxs)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addressEditBackdrop")
        .task(id: session.text) {
            let results = await Self.googleSuggestions(for: session.text, enabled: fetchesGoogle)
            if !Task.isCancelled { google = results }
        }
    }

    /// Google's suggestions for typed text, after a short pause in typing.
    private static func googleSuggestions(for text: String, enabled: Bool) async -> [String] {
        guard let q = GoogleSuggestClient.query(forTyped: text, enabled: enabled) else { return [] }
        do { try await Task.sleep(for: googleDebounce) } catch { return [] }
        return await GoogleSuggestClient.suggestions(for: q)
    }

    private var recentSearchesList: some View {
        VStack(spacing: 0) {
            SectionHeader(title: Verbs.recentSearches, size: .page, actionTitle: Verbs.clearAll,
                          actionIdentifier: "recentSearchesClear", action: onClearRecentSearches)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xs)

            ForEach(recentSearches, id: \.self) { term in
                SymbolRowSeparator(leadingInset: Spacing.m)
                SuggestionRow(title: term, subtitle: nil, openLabel: term, onOpen: { onSubmit(term) },
                              onFill: { session.fill(term) }) {
                    Image(systemName: Icons.search).foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }

    private func suggestionsList(_ rows: [AddressSuggestion]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                SuggestionRow(title: row.title, subtitle: row.subtitle, onOpen: { onSubmit(row.query) },
                              onFill: { session.fill(row.query) }) {
                    switch row.kind {
                    case .recent, .saved:
                        ArtworkTile(image: row.faviconData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                                    letter: PageTitle.artworkLetter(title: row.title, source: row.host, address: row.query),
                                    size: Glyph.rowLeading)
                    case .google:
                        Image(systemName: Icons.search).foregroundStyle(Palette.secondaryInk)
                    }
                }
                if row.id != rows.last?.id {
                    SymbolRowSeparator(leadingInset: Spacing.m)
                }
            }
        }
    }
}

/// One row of the search layer (a `SymbolRow`): tap opens it; the ↖︎ arrow (Safari's fill
/// control) puts it in the field without opening.
private struct SuggestionRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    /// Accessibility label of the open button, when its icon would otherwise be read too.
    var openLabel: String? = nil
    let onOpen: () -> Void
    let onFill: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 0) {
            if let openLabel {
                openButton.accessibilityLabel(openLabel)
            } else {
                openButton
            }

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
            .padding(.trailing, Spacing.xxs)
        }
    }

    private var openButton: some View {
        Button(action: onOpen) {
            SymbolRow(title, subtitle: subtitle, leading: leading) { EmptyView() }
                .padding(.leading, Spacing.m)
        }
        .buttonStyle(.plain)
    }
}

extension EnvironmentValues {
    /// Live Google suggestions in the address field; a launch turns them off for UI tests, so
    /// results don't depend on the network.
    @Entry var fetchesSearchSuggestions = true
}
