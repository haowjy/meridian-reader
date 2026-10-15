import SwiftUI

/// The address search session's full-bleed layer over the page (Safari): Recent Searches while
/// the field is untouched, otherwise suggestions (history, saved articles, Google). Scrolling the
/// list drags the keyboard down with the finger (the system's interactive dismissal); with
/// nothing to list, a swipe down lowers it. Either way the session stays.
struct SearchSessionOverlay: View {
    let session: SearchSession
    let recentSearches: [String]
    let visits: [RecentVisit]
    let articles: [Page]
    var isDictating: Bool
    var onSubmit: (String) -> Void
    var onClearRecentSearches: () -> Void

    @State private var google: [String] = []

    /// Live Google suggestions; off in UI tests so results don't depend on the network.
    #if DEBUG
    private static let fetchesGoogle = LaunchOptions.current.fetchesSuggestions
    #else
    private static let fetchesGoogle = true
    #endif
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
            let results = await Self.googleSuggestions(for: session.text)
            if !Task.isCancelled { google = results }
        }
    }

    /// Google's suggestions for typed text, after a short pause in typing.
    private static func googleSuggestions(for text: String) async -> [String] {
        guard let q = GoogleSuggestClient.query(forTyped: text, enabled: fetchesGoogle) else { return [] }
        do { try await Task.sleep(for: googleDebounce) } catch { return [] }
        return await GoogleSuggestClient.suggestions(for: q)
    }

    private var recentSearchesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Searches")
                    .typeStyle(.heading, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear All", action: onClearRecentSearches)
                    .typeStyle(.row)
                    .accessibilityIdentifier("recentSearchesClear")
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xs)

            ForEach(recentSearches, id: \.self) { term in
                Divider().padding(.leading, SuggestionRow<EmptyView>.textInset)
                SuggestionRow(title: term, subtitle: nil, openLabel: term, onOpen: { onSubmit(term) },
                              onFill: { session.fill(term) }) {
                    Image(systemName: Icons.search)
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: SuggestionRow<EmptyView>.leadingWidth)
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
                        FaviconImage(data: row.faviconData, host: row.host,
                                     size: SuggestionRow<EmptyView>.leadingWidth)
                    case .google:
                        Image(systemName: Icons.search)
                            .font(.body)
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: SuggestionRow<EmptyView>.leadingWidth,
                                   height: SuggestionRow<EmptyView>.leadingWidth)
                    }
                }
                if row.id != rows.last?.id {
                    Divider().padding(.leading, SuggestionRow<EmptyView>.textInset)
                }
            }
        }
    }
}

/// One row of the search layer: tap opens it; the ↖︎ arrow (Safari's fill control) puts it in
/// the field without opening.
private struct SuggestionRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    /// Accessibility label of the open button, when its icon would otherwise be read too.
    var openLabel: String? = nil
    let onOpen: () -> Void
    let onFill: () -> Void
    @ViewBuilder let leading: () -> Leading

    /// Width of the leading icon.
    static var leadingWidth: CGFloat { 28 }
    /// Where the title starts: dividers line up with it.
    static var textInset: CGFloat { Spacing.m + leadingWidth + Spacing.s }

    var body: some View {
        HStack(spacing: 0) {
            if let openLabel {
                openButton.accessibilityLabel(openLabel)
            } else {
                openButton
            }

            Button(action: onFill) {
                Image(systemName: Icons.fillField)
                    .font(.body.weight(.medium))
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
            HStack(spacing: Spacing.s) {
                leading()
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .typeStyle(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Spacing.m)
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
