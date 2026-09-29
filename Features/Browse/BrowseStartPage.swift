import SwiftUI
import SwiftData
import UIKit

// MARK: - Start page

/// The browser's start page (no page loaded), Safari-style: a Bookmarks icon grid (site
/// bookmarks, like Safari Favorites), "Continue listening", recent "Saved" articles with Show All
/// (opens the library sheet), then Recent Searches.
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
        guard let paragraphs = article.cachedListenParagraphs, !paragraphs.isEmpty else { return 0 }
        let map = ReaderScrubMap(paragraphs: paragraphs)
        let p = min(max(0, article.playbackParagraphIndex), paragraphs.count - 1)
        // Stored offsets index the joined listen text (paragraphs + "\n\n" separators).
        let before = paragraphs[..<p].reduce(0) { $0 + $1.utf16.count + 2 }
        let within = Double(max(0, article.playbackUTF16Offset - before)) / Double(max(1, paragraphs[p].utf16.count))
        return map.fraction(paragraph: p, within: min(within, 1))
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

struct ThinProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22))
                Capsule().fill(Color.accentColor).frame(width: g.size.width * min(max(0, value), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Mini player

/// Slim now-playing bar above the browser toolbar while an article is loaded for playback and the
/// reader isn't on screen: title, progress, play/pause. Tap it to open the reader.
struct MiniPlayerBar: View {
    @Bindable var speech: SpeechController
    var onOpen: () -> Void
    /// Bar width (= the toolbar row's width): play/pause sits over the ⋯ slot (Nav I).
    @State private var width: CGFloat = 0

    /// Play/pause button width.
    static let playSize: CGFloat = 40

    /// Trailing padding that centers play/pause on slot 5 of `BottomToolbarLayout`.
    static func trailingPadding(rowWidth: CGFloat) -> CGFloat {
        guard rowWidth > 0 else { return 4 }
        return max(4, BottomToolbarLayout.slotWidth(rowWidth: rowWidth) / 2 - playSize / 2)
    }

    var body: some View {
        if let id = speech.activeSessionID {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(speech.nowPlayingTitle ?? "Now playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("miniPlayerTitle")
                    ThinProgressBar(value: progress)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the reader")
                .accessibilityIdentifier("miniPlayerOpen")
                .accessibilityAction(.default, onOpen)

                let playing = speech.showsPauseIcon(for: id)
                Button {
                    if playing { speech.pause() } else { speech.resume() }
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: Self.playSize, height: Self.playSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Pause" : "Play")
                .accessibilityIdentifier("miniPlayerPlayPause")
            }
            .padding(.leading, 14)
            .padding(.trailing, Self.trailingPadding(rowWidth: width))
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 != width { width = $0 } }
            .contextMenu {
                Button("Stop listening", systemImage: "stop.fill") { speech.stop() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("miniPlayer")
        }
    }

    /// Text-length weighted, like the scrubber.
    private var progress: Double {
        let total = (speech.document.joinedText as NSString).length
        guard total > 0 else { return 0 }
        return min(1, Double(speech.spokenUTF16Offset) / Double(total))
    }
}

// MARK: - ⋯ popover

/// Safari-style ⋯ popover: action rows, then a row of big buttons (Bookmarks, Saved, History).
struct BrowseMoreMenu: View {
    enum Action { case newSearch, toggleSave, toggleBookmark, share, reload, voiceSettings, listenDebug,
                     bookmarks, saved, history, toggleReader, openWebsite }

    /// The same panel (`MorphMenuOverlay`) is the menu on the web page / start page and inside the
    /// reader; only the top rows differ. The bottom row is `[Bookmarks][Saved][History][Reader]` on a
    /// page and `[Bookmarks][Saved][History][Website]` in the reader: the rightmost button (nearest
    /// the thumb) switches between the page and its reader view. Its icon is the panel's focus
    /// point: `MorphMenuOverlay` puts it exactly where the ⋯ glyph was (Nav H).
    enum Context { case browse, reader }

    var context: Context = .browse
    let hasPage: Bool
    /// Reader toggle enabled: a readable page (Browse) / always (inside the reader).
    let canToggleReader: Bool
    /// Reader mode is showing: the toggle is drawn selected and tapping it leaves reader mode.
    var isReaderOn: Bool = false
    /// Reader context: the article has a web page to go to (the Website button).
    var canOpenWebsite: Bool = false
    let isSaved: Bool
    let canSave: Bool
    let isBookmarked: Bool
    let canBookmark: Bool
    let canShare: Bool
    /// Developer options: show the Debug row (hidden in Release unless unlocked).
    var showsDebug: Bool = false
    @Binding var fakeExtractionFailure: Bool
    var onAction: (Action) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch context {
            case .browse:
                row("New search", "magnifyingglass", .newSearch, id: "moreNewSearch")
                saveRow
                bookmarkRow
                shareRow
                row("Reload", "arrow.clockwise", .reload, id: "moreReload")
                    .disabled(!hasPage)
                voiceRow
                if showsDebug {
                    Menu {
                        Toggle("Fake extraction failure", isOn: $fakeExtractionFailure)
                    } label: {
                        rowLabel("Debug", "ladybug", trailing: "chevron.right")
                    }
                    .accessibilityIdentifier("moreDebug")
                }
            case .reader:
                voiceRow
                saveRow
                bookmarkRow
                shareRow
                if showsDebug {
                    row("Debug", "ladybug", .listenDebug, id: "moreDebug")
                }
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            HStack(spacing: 0) {
                bigButton("Bookmarks", "star", .bookmarks, id: "moreBookmarks")
                bigButton("Saved", "books.vertical", .saved, id: "moreLibrary")
                bigButton("History", "clock", .history, id: "moreHistory")
                switch context {
                case .browse:
                    bigButton("Reader", isReaderOn ? "doc.plaintext.fill" : "doc.plaintext", .toggleReader,
                              id: "moreReaderToggle", selected: isReaderOn, focus: true)
                        .disabled(!canToggleReader)
                        .accessibilityLabel(isReaderOn ? "Reader, on" : "Reader")
                        .accessibilityHint(isReaderOn ? "Back to the web page" : "Open in Reader")
                case .reader:
                    // Reader off = the article's own web page, from anywhere (library, start page,
                    // Continue listening, mini player). Playback keeps going.
                    bigButton("Website", "globe", .openWebsite, id: "moreWebsite", focus: true)
                        .disabled(!canOpenWebsite)
                        .accessibilityLabel("View Website")
                        .accessibilityHint("Opens the article's web page")
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 10)
        .frame(width: 300)
    }

    private var saveRow: some View {
        row(isSaved ? "Remove from Saved" : "Save article",
            // Saved article = the bookmark glyph (same as the reader's save button);
            // site bookmarks use the star.
            isSaved ? "bookmark.slash" : "bookmark", .toggleSave, id: "moreSave")
            .disabled(!canSave)
    }

    private var bookmarkRow: some View {
        row(isBookmarked ? "Remove Bookmark" : "Bookmark", isBookmarked ? "star.slash" : "star",
            .toggleBookmark, id: "moreBookmark")
            .disabled(!canBookmark)
    }

    private var shareRow: some View {
        row("Share", "square.and.arrow.up", .share, id: "moreShare")
            .disabled(!canShare)
    }

    private var voiceRow: some View {
        row("Voice settings", "person.wave.2", .voiceSettings, id: "moreVoice")
    }

    private func row(_ title: String, _ icon: String, _ action: Action, id: String) -> some View {
        Button { onAction(action) } label: { rowLabel(title, icon) }
            .buttonStyle(MenuRowStyle())
            .accessibilityIdentifier(id)
    }

    private func rowLabel(_ title: String, _ icon: String, trailing: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 24)
            Text(title)
                .font(.body)
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func bigButton(_ title: String, _ icon: String, _ action: Action, id: String,
                           selected: Bool = false, focus: Bool = false) -> some View {
        Button { onAction(action) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .morphMenuFocus(focus)
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(selected ? 0.14 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle(cornerRadius: 12))
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pressed-state highlight for popover rows (like a system menu).
private struct MenuRowStyle: ButtonStyle {
    var cornerRadius: CGFloat = 0
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.35)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
    }
}

// MARK: - History

/// Recently visited pages (the bounded `RecentVisit` list). Tap to open.
struct BrowseHistoryView: View {
    let visits: [RecentVisit]
    var onOpen: (RecentVisit) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock",
                                           description: Text("Pages you open show up here."))
                } else {
                    List(visits, id: \.id) { visit in
                        Button { onOpen(visit) } label: {
                            HStack(spacing: 12) {
                                FaviconImage(data: visit.faviconData, host: visit.host, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(visit.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(visit.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text(visit.visitedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("browseHistory")
    }
}

// MARK: - Share

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Bookmarks

/// Safari-Favorites-style grid: icon tile + title. Long-press → Rename / Delete.
struct BookmarkGrid: View {
    let bookmarks: [SiteBookmark]
    var onOpen: (SiteBookmark) -> Void
    var onDelete: (SiteBookmark) -> Void
    var onRename: (SiteBookmark, String) -> Void

    @State private var renaming: SiteBookmark?
    @State private var renameText = ""

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4),
                  spacing: 14) {
            ForEach(bookmarks) { bookmark in
                Button { onOpen(bookmark) } label: {
                    VStack(spacing: 6) {
                        BookmarkIcon(bookmark: bookmark, size: 60)
                        Text(bookmark.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmark.title)
                .accessibilityIdentifier("bookmarkTile")
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") {
                        renameText = bookmark.title
                        renaming = bookmark
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete(bookmark) }
                }
            }
        }
        .alert("Rename Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming { onRename(renaming, renameText) }
                renaming = nil
            }
        }
    }
}

/// Site icon on a rounded tile, or a colored letter tile when there's no (usable) icon.
struct BookmarkIcon: View {
    let bookmark: SiteBookmark
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            if let image = icon {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.56, height: size * 0.56)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(tint.gradient)
                Text(letter)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var icon: UIImage? {
        // Tiny 16 px icons look smeared on a big tile; the letter tile reads better.
        guard FaviconFetcher.isTileSized(bookmark.faviconData),
              let data = bookmark.faviconData else { return nil }
        return UIImage(data: data)
    }

    private var letter: String {
        let source = bookmark.title.first(where: { $0.isLetter || $0.isNumber })
            ?? bookmark.host.replacingOccurrences(of: "www.", with: "").first
        return source.map { String($0).uppercased() } ?? "?"
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .brown]
        let hash = bookmark.host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

/// All bookmarks: tap to open, swipe or Edit to delete / reorder.
struct BookmarksListView: View {
    @Bindable var store: BookmarkStore
    var onOpen: (SiteBookmark) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks", systemImage: "star",
                                           description: Text("Open a site, then ⋯ → Bookmark."))
                } else {
                    List {
                        ForEach(store.bookmarks) { bookmark in
                            Button { onOpen(bookmark) } label: {
                                HStack(spacing: 12) {
                                    BookmarkIcon(bookmark: bookmark, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bookmark.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(bookmark.host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { store.remove(atOffsets: $0) }
                        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.bookmarks.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
        }
        .accessibilityIdentifier("bookmarksList")
    }
}
