import SwiftUI
import SwiftData

/// The browser's start page (no page loaded), Safari-style: a Bookmarks icon grid (site
/// bookmarks, like Safari Favorites), "Continue listening", recent "Saved" articles with Show All
/// (opens the library), then Recent Searches.
struct BrowseStartPage: View {
    let bookmarks: [SiteBookmark]
    /// In-progress saved articles, most recently listened first (all of them; up to 3 shown).
    let continueListening: [SavedArticle]
    /// Kept articles, newest first (all of them; the first few not already above are shown).
    let saved: [SavedArticle]
    let recentSearches: [String]
    var onOpenBookmark: (SiteBookmark) -> Void
    var onShowBookmarks: () -> Void
    var onDeleteBookmark: (SiteBookmark) -> Void
    var onRenameBookmark: (SiteBookmark, String) -> Void
    var onOpenArticle: (SavedArticle) -> Void
    var onShowLibrary: () -> Void
    var onSearch: (String) -> Void
    var onClearSearches: () -> Void

    /// Two rows of four; Show All lists them all (and edits / reorders).
    static let bookmarkLimit = 8
    static let continueLimit = 3
    static let savedLimit = 4

    private var continueShown: [SavedArticle] { Array(continueListening.prefix(Self.continueLimit)) }

    private var savedShown: [SavedArticle] {
        let skip = Set(continueShown.map(\.id))
        return Array(saved.filter { !skip.contains($0.id) }.prefix(Self.savedLimit))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !bookmarks.isEmpty {
                    section("Bookmarks", id: "startBookmarks", showAll: onShowBookmarks) {
                        BookmarkGrid(bookmarks: Array(bookmarks.prefix(Self.bookmarkLimit)),
                                     onOpen: onOpenBookmark, onDelete: onDeleteBookmark,
                                     onRename: onRenameBookmark)
                    }
                }

                if !continueShown.isEmpty {
                    section("Continue listening", id: "startContinue",
                            showAll: continueListening.count > Self.continueLimit ? onShowLibrary : nil) {
                        rows(continueShown) { article in
                            ArticleRow(article: article, progress: Self.progress(of: article))
                        }
                    }
                }

                if !savedShown.isEmpty {
                    section("Saved", id: "startSaved", showAll: onShowLibrary) {
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("browseStartPage")
    }

    /// Fraction listened, weighted by text length (same measure as the reader's scrubber).
    static func progress(of article: SavedArticle) -> Double {
        guard let paragraphs = article.cachedListenParagraphs else { return 0 }
        return progress(paragraphs: paragraphs, paragraph: article.playbackParagraphIndex,
                        utf16Offset: article.playbackUTF16Offset)
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

    private func section<Content: View>(_ title: String, id: String, showAll: (() -> Void)?,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let showAll {
                    Button(action: showAll) {
                        HStack(spacing: 3) {
                            Text("Show All")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("\(id)ShowAll")
                }
            }
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    private func rows<Row: View>(_ articles: [SavedArticle], @ViewBuilder row: @escaping (SavedArticle) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(articles, id: \.id) { article in
                Button { onOpenArticle(article) } label: {
                    row(article)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if article.id != articles.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Searches")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear", action: onClearSearches)
                    .font(.subheadline)
                    .accessibilityIdentifier("startSearchesClear")
            }
            VStack(spacing: 0) {
                ForEach(recentSearches, id: \.self) { term in
                    Button { onSearch(term) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(term)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if term != recentSearches.last {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startRecentSearches")
    }
}

private struct ArticleRow: View {
    let article: SavedArticle
    /// Non-nil: a thin progress bar (Continue listening).
    let progress: Double?

    var body: some View {
        HStack(spacing: 12) {
            FaviconImage(data: article.faviconData, host: article.siteDomain, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress {
                    ThinProgressBar(value: progress)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.map { "\(Int(($0 * 100).rounded())) percent listened" } ?? "")
    }

    private var subtitle: String {
        guard let progress else { return "\(article.siteDomain) · \(article.estimatedMinutes) min" }
        let left = max(1, Int((Double(article.estimatedMinutes) * (1 - progress)).rounded()))
        return "\(article.siteDomain) · \(left) min left"
    }
}
