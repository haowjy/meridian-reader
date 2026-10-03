import SwiftUI

/// The address search session's full-bleed layer over the page (Safari): Recent Searches while
/// the field is untouched, otherwise suggestions (history, saved articles, Google). Scrolling the
/// list drags the keyboard down with the finger (the system's interactive dismissal); with
/// nothing to list, a swipe down lowers it. Either way the session stays.
struct SearchSessionOverlay: View {
    let session: SearchSession
    let recentSearches: [String]
    let visits: [RecentVisit]
    let articles: [SavedArticle]
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
                                        articles: articles, google: google)
    }

    var body: some View {
        let suggestions = suggestions
        ZStack(alignment: .top) {
            Color(.systemBackground)
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
                    .padding(.top, 4)
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
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear All", action: onClearRecentSearches)
                    .font(.body)
                    .accessibilityIdentifier("recentSearchesClear")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(recentSearches, id: \.self) { term in
                Divider().padding(.leading, 52)
                SuggestionRow(title: term, subtitle: nil, openLabel: term, onOpen: { onSubmit(term) },
                              onFill: { session.fill(term) }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
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
                        FaviconImage(data: row.faviconData, host: row.host, size: 28)
                    case .google:
                        Image(systemName: "magnifyingglass")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                }
                if row.id != rows.last?.id {
                    Divider().padding(.leading, 52)
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

    var body: some View {
        HStack(spacing: 0) {
            if let openLabel {
                openButton.accessibilityLabel(openLabel)
            } else {
                openButton
            }

            Button(action: onFill) {
                Image(systemName: "arrow.up.backward")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Insert into search field")
            .padding(.trailing, 6)
        }
    }

    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                leading()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
