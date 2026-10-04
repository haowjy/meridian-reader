import SwiftUI
import SwiftData
import WebKit

/// The browser, and the root of the shell: the web page or start page with its bottom chrome,
/// the address search layer, and over it whichever surface `ShellState` says is up (the
/// reader overlay or the library), the one ⋯ menu overlay and the one sheet.
struct BrowseStartView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    /// Once true, the browse WKWebView stays in the tree (history / back-forward). Starts false so
    /// cold launch on the start page never creates WebKit GPU/WebContent processes.
    @State private var browseWebViewMounted = false
    /// Address-bar dictation, made on the first mic tap.
    @State private var dictation: AddressDictation?
    @AppStorage(RecentSearches.storageKey) private var recentSearchesRaw = ""
    @State private var alertMessage: String?
    @State private var useFakeFailure = false
    /// Site bookmarks (their own JSON store; not the saved-article model).
    @State private var bookmarkStore = BookmarkStore.shared
    @State private var listenHistory = ListenHistory(defaults: .standard)

    private var webStore: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }

    private var isReaderShown: Bool { shell.readerArticle != nil }

    /// Bottom-bar bookmark reflects "already saved" for the current page's canonical URL.
    private var currentSavedArticle: SavedArticle? {
        guard let url = webStore.currentURL, url.isWeb else { return nil }
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        return articles.first { $0.canonicalURL == canonical }
    }

    private var hasPage: Bool { webStore.hasPage }

    /// Create the browse WKWebView only after the first non-start navigation; keep it thereafter.
    private var showsBrowseWebView: Bool {
        browseWebViewMounted || hasPage
    }

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesRaw) }

    var body: some View {
        browser
            // Under the reader overlay the browser stays as it is (so pulling the reader down
            // reveals it), but it is out of reach until the reader is gone.
            .allowsHitTesting(!isReaderShown)
            .accessibilityHidden(isReaderShown)
            // While searching, avoid the keyboard so the field sits right above it. Otherwise keep
            // ignoring it (typing into a web page must not resize the page / the web view).
            .ignoresSafeArea(.keyboard, edges: search.isFocused ? [] : .bottom)
            // The reader and the library cover the whole browser, edge to edge. Outside the page
            // ZStack, whose `.clipped()` would cut them at the safe area.
            .overlay { surfaceOverlay }
            // Every surface's ⋯ menu: grows out of its button and covers it (Safari iOS 26), over
            // everything else (the library's navigation bar too).
            .overlay { menuOverlay }
            .background {
                ListenHistoryRecorder(speech: speech) { activeID in
                    listenHistory = ListenHistory(defaults: .standard)
                    shell.noteActiveSession(activeID)
                }
            }
            .sheet(item: Binding(get: { shell.sheet }, set: { shell.sheet = $0 })) { ShellSheetView(sheet: $0) }
            .modifier(BrowseAlerts(extractionError: $alertMessage, dictation: dictation))
            .onChange(of: webStore.currentURL) { _, _ in shell.syncAddressField() }
            .onChange(of: webStore.isLoading) { _, loading in
                guard !loading else { return }
                run { await $0.recordVisit() }
            }
            .onChange(of: search.text) { _, text in
                // Typing (or clearing) while dictating takes over from the mic.
                if let dictation, dictation.isListening, text != dictation.transcript {
                    dictation.stop()
                }
            }
            // Leaving the field (✕, navigating, swipe-down) closes the mic.
            .onChange(of: search.isFocused) { _, focused in
                if !focused { dictation?.cancel() }
            }
    }

    /// The page (or start page), the search layer over it, and the bottom chrome.
    private var browser: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsBrowseWebView {
                    WebView(store: webStore)
                        .opacity(hasPage ? 1 : 0)
                        .allowsHitTesting(hasPage)
                        .onAppear { browseWebViewMounted = true }
                }

                if !hasPage {
                    startPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Safari-style search session: full-bleed Recent Searches / suggestions over the page.
            .overlay {
                if search.isActive && shell.isBrowsing {
                    searchLayer
                }
            }
            .clipped()

            // The library draws its own chrome and covers this; the reader overlay draws its own
            // too, but this stays under it so its pull-down reveals the browser whole.
            if !shell.isInLibrary {
                bottomChrome
            }
        }
        // The page area is clipped to the safe area; when paper shows there (the start page, the
        // search layer), it continues up under the status bar.
        .background {
            if !hasPage || search.isActive {
                Palette.paper.ignoresSafeArea()
            }
        }
    }

    private var searchLayer: some View {
        SearchSessionOverlay(
            session: search,
            recentSearches: recentSearches,
            visits: recentVisits,
            articles: articles,
            isDictating: dictation?.isActive == true,
            onSubmit: submit,
            onClearRecentSearches: { recentSearchesRaw = "" }
        )
    }

    private var bottomChrome: some View {
        BrowserBottomChrome(
            speech: speech,
            dictation: dictation,
            onOpenReader: { run { try await $0.openInReader() } },
            onSubmit: { submit(search.text) },
            onMic: toggleDictation,
            onOpenLibrary: shell.openLibrary,
            onOpenNowPlaying: {
                if let id = speech.activeSessionID { shell.openNowPlaying(id, in: modelContext) }
            },
            menu: { .browse(browseMenu, perform: perform) }
        )
    }

    private var menuOverlay: some View {
        MorphMenuOverlay(item: Binding(get: { shell.menu }, set: { shell.menu = $0 }),
                         anchor: shell.menuAnchor) { context, close in
            MoreMenuPanel(context: context, close: close)
        }
    }

    // MARK: - Surfaces

    /// The reader overlay or the library, over the browser.
    @ViewBuilder
    private var surfaceOverlay: some View {
        switch shell.surface {
        case .browse:
            EmptyView()
        case .reader(let article, let origin):
            readerOverlay(for: article, origin: origin)
                .transition(.sheet(reduceMotion: reduceMotion))
        case .library:
            LibrarySurface(path: Binding(get: { shell.libraryPath }, set: { shell.libraryPath = $0 }))
                .transition(.opacity)
        }
    }

    private func readerOverlay(for article: ReaderArticle, origin: ReaderOrigin) -> some View {
        ArticleReaderScreen(
            article: article,
            presentation: .overlay,
            origin: origin,
            speech: speech,
            onClose: shell.hideReader,
            onIdentityChange: { newID in shell.updateReader(id: article.id) { $0.id = newID } }
        )
    }

    // MARK: - ⋯ menu

    private var shareURL: URL? {
        webStore.currentURL.flatMap { $0.isWeb ? $0 : nil }
    }

    private var browseMenu: BrowseMenu {
        BrowseMenu(
            hasPage: hasPage,
            canOpenReader: canOpenReader,
            isSaved: currentSavedArticle != nil,
            canSave: hasPage && shell.busy == nil,
            isBookmarked: currentBookmark != nil,
            canBookmark: webStore.currentURL.map(BookmarkStore.isBookmarkable) ?? false,
            canShare: shareURL != nil,
            fakeExtractionFailure: speech.developerOptionsEnabled ? $useFakeFailure : nil
        )
    }

    private func perform(_ action: BrowseMenu.Action) {
        switch action {
        case .newSearch: shell.showStartPage()
        case .openReader: run { try await $0.openInReader() }
        case .toggleSave: toggleSave()
        case .toggleBookmark: run { page in await page.toggleBookmark(in: bookmarkStore) }
        case .bookmarks: shell.present(.bookmarks)
        case .reload: webStore.refresh()
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .voiceSettings: shell.present(.voiceSettings)
        case .saved: shell.openLibrary()
        case .history: shell.present(.history)
        }
    }

    private var canOpenReader: Bool { hasPage && webStore.isReaderable && shell.busy == nil }

    private var currentBookmark: SiteBookmark? {
        bookmarkStore.bookmark(for: webStore.currentURL)
    }

    // MARK: - Start page

    private var startPage: some View {
        BrowseStartPage(
            bookmarks: bookmarkStore.bookmarks,
            continueListening: ContinueListening.articles(articles, history: listenHistory),
            saved: articles,
            recentSearches: recentSearches,
            onOpenBookmark: { if let url = $0.url { shell.navigate(to: url) } },
            onShowBookmarks: { shell.present(.bookmarks) },
            onDeleteBookmark: { bookmarkStore.remove(id: $0.id) },
            onRenameBookmark: { bookmarkStore.rename(id: $0.id, to: $1) },
            onOpenArticle: { shell.openSaved($0.id, in: modelContext) },
            onShowLibrary: shell.openLibrary,
            onSearch: submit,
            onClearSearches: { recentSearchesRaw = "" }
        )
        .task(id: bookmarkStore.bookmarks.count) { await bookmarkStore.backfillIcons() }
    }

    // MARK: - Address

    /// Submitted address field, recent search or suggestion: remember a search term, then load.
    private func submit(_ text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = BrowseURLParser.destination(from: raw) else { return }
        if RecentSearches.isSearch(raw) {
            recentSearchesRaw = RecentSearches.encode(RecentSearches.adding(raw, to: recentSearches))
        }
        shell.navigate(to: url)
    }

    /// 🎤: start dictating into an empty field (a fresh search), or stop.
    private func toggleDictation() {
        let dictation = dictation ?? makeDictation()
        if dictation.isActive {
            dictation.stop()
        } else {
            dictation.start()
            search.begin()
        }
    }

    private func makeDictation() -> AddressDictation {
        let made = AddressDictation(recognizer: SystemDictationRecognizer(),
                                    audio: ListenDictationHandoff(speech: speech))
        made.onTranscript = { [search, weak made] text in
            if search.isFocused || made?.isActive == true { search.text = text }
        }
        dictation = made
        return made
    }

    // MARK: - Page actions

    /// The loaded page as an article. Developer options can force extraction to fail.
    private var page: PageArticleService {
        PageArticleService(shell: shell,
                           extractor: useFakeFailure ? FakeArticleExtractor(mode: .failure) : extractor,
                           context: modelContext, speech: speech, recentVisits: recentVisits)
    }

    /// Runs a page action; a failed extraction shows the alert.
    private func run(_ action: @escaping (PageArticleService) async throws -> Void) {
        let page = page
        Task {
            do { try await action(page) } catch { alertMessage = error.localizedDescription }
        }
    }

    /// ⋯ → Save article / Remove from Saved, by canonical URL.
    private func toggleSave() {
        if let saved = currentSavedArticle {
            ArticleSaveCoordinator(context: modelContext, speech: speech)
                .unsave(id: saved.id, canonicalURL: saved.canonicalURL)
        } else {
            run { try await $0.save() }
        }
    }
}
