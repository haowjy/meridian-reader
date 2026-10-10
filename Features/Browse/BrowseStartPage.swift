import SwiftUI

/// The browser's start page (no page loaded), Safari-style: a Bookmarks icon grid (Favorites'
/// pages, like Safari Favorites), "Continue listening" (Show All lists the rest in place), recent
/// "Saved" articles with Show All (opens the library), then Recent Searches.
struct BrowseStartPage: View {
    let bookmarks: [Page]
    /// Pages part-way through, most recently listened first (`LibraryQueries.continuePages`; up
    /// to 3 shown until Show All).
    let continueListening: [Page]
    /// Saved pages in no folder, newest first (all of them; the first few not already above are
    /// shown).
    let saved: [Page]
    let recentSearches: [String]
    var onOpenBookmark: (Page) -> Void
    var onShowBookmarks: () -> Void
    var onDeleteBookmark: (Page) -> Void
    var onRenameBookmark: (Page, String) -> Void
    var onOpenArticle: (Page) -> Void
    var onShowLibrary: () -> Void
    var onSearch: (String) -> Void
    var onClearSearches: () -> Void

    /// Two rows of four; Show All lists them all (and edits / reorders).
    static let bookmarkLimit = 8
    static let continueLimit = 3
    static let savedLimit = 4
    /// Width of a recent search's clock glyph.
    private static let searchIconWidth: CGFloat = 20

    /// Continue shows every row (Show All tapped). In place, because some of them (pages played
    /// without saving, saved pages filed in Favorites) aren't in the Library's list.
    @State private var continueExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var continueShown: [Page] { Self.continueRows(continueListening, expanded: continueExpanded) }

    /// The Continue header's action.
    enum ContinueAction: Equatable {
        case showAll
        case showLess
    }

    /// Continue's rows: the first `continueLimit`, or all of them once expanded.
    static func continueRows(_ all: [Page], expanded: Bool) -> [Page] {
        expanded ? all : Array(all.prefix(continueLimit))
    }

    /// Show All while some rows are hidden, Show Less once expanded; none when all fit.
    static func continueAction(count: Int, expanded: Bool) -> ContinueAction? {
        guard count > continueLimit else { return nil }
        return expanded ? .showLess : .showAll
    }

    private var savedShown: [Page] {
        let skip = Set(continueShown.map(\.listenKey))
        return Array(saved.filter { !skip.contains($0.listenKey) }.prefix(Self.savedLimit))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if !bookmarks.isEmpty {
                    section("Bookmarks", id: "startBookmarks", action: onShowBookmarks) {
                        BookmarkGrid(bookmarks: Array(bookmarks.prefix(Self.bookmarkLimit)),
                                     onOpen: onOpenBookmark, onDelete: onDeleteBookmark,
                                     onRename: onRenameBookmark)
                    }
                }

                if !continueShown.isEmpty {
                    let action = Self.continueAction(count: continueListening.count, expanded: continueExpanded)
                    section("Continue listening", id: "startContinue",
                            action: action.map { _ in toggleContinue },
                            actionTitle: action == .showLess ? "Show Less" : "Show All", navigates: false) {
                        rows(continueShown) { article in
                            ArticleRow(article: article, progress: Self.progress(of: article))
                        }
                    }
                }

                if !savedShown.isEmpty {
                    section("Saved", id: "startSaved", action: onShowLibrary) {
                        rows(savedShown) { article in
                            ArticleRow(article: article, progress: nil)
                        }
                    }
                }

                if !recentSearches.isEmpty {
                    recentSearchesSection
                }

                if bookmarks.isEmpty && continueShown.isEmpty && savedShown.isEmpty && recentSearches.isEmpty {
                    Text("Search or enter an address below. Sites you bookmark and articles you save or listen to show up here.")
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

    /// Fraction listened, weighted by text length (same measure as the reader's scrubber).
    static func progress(of article: Page) -> Double {
        guard let paragraphs = article.cachedListenParagraphs else { return 0 }
        return progress(paragraphs: paragraphs, paragraph: article.positionParagraph,
                        utf16Offset: article.positionUTF16)
    }

    /// `utf16Offset` indexes the article's listen text (`ParagraphDocument.joinedText`). Only
    /// paragraph lengths matter here, so the scrub map skips sentence tokenizing.
    static func progress(paragraphs: [String], paragraph: Int, utf16Offset: Int) -> Double {
        let document = ParagraphDocument(parts: paragraphs)
        guard !document.isEmpty else { return 0 }
        let p = min(max(0, paragraph), document.count - 1)
        let map = ReaderScrubMap(paragraphs: document.paragraphs, sentences: false)
        return map.fraction(paragraph: p, offset: utf16Offset - document.startUTF16Offset(forParagraph: p))
    }

    private func toggleContinue() {
        withAnimation(reduceMotion ? nil : Motion.standard) { continueExpanded.toggle() }
    }

    /// A section with its title and, given `action`, a trailing button (`<id>ShowAll`); a › after
    /// it when it `navigates` somewhere rather than changing this page.
    private func section<Content: View>(_ title: String, id: String, action: (() -> Void)?,
                                        actionTitle: LocalizedStringKey = "Show All", navigates: Bool = true,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .typeStyle(.heading)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let action {
                    Button(action: action) {
                        HStack(spacing: Spacing.xxs) {
                            Text(actionTitle)
                            if navigates {
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                        }
                        .typeStyle(.row)
                    }
                    .accessibilityIdentifier("\(id)ShowAll")
                }
            }
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    private func rows<Row: View>(_ articles: [Page], @ViewBuilder row: @escaping (Page) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(articles, id: \.listenKey) { article in
                Button { onOpenArticle(article) } label: {
                    row(article)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if article.listenKey != articles.last?.listenKey {
                    Divider().padding(.leading, Spacing.s + ArticleRow.iconSize + Spacing.s)
                }
            }
        }
        .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card))
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

private struct ArticleRow: View {
    let article: Page
    /// Non-nil: a thin progress bar (Continue listening).
    let progress: Double?

    /// The site icon's size.
    static let iconSize: CGFloat = 32

    var body: some View {
        HStack(spacing: Spacing.s) {
            FaviconImage(data: article.artworkData, host: article.byline, size: Self.iconSize)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(article.title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                if let progress {
                    ThinProgressBar(value: progress)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.map { "\(Int(($0 * 100).rounded())) percent listened" } ?? "")
    }

    private var subtitle: String {
        guard let progress else { return "\(article.byline) · \(article.estimatedMinutes) min" }
        let left = max(1, Int((Double(article.estimatedMinutes) * (1 - progress)).rounded()))
        return "\(article.byline) · \(left) min left"
    }
}
