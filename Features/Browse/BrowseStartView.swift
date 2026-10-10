import SwiftUI
import SwiftData
import WebKit

/// The browser, and the root of the shell: the web page or start page with its bottom chrome,
/// the address search layer, and over it the layers `ShellState` says are up, in order: the
/// library, the Reader sheet, Now Playing, the one ⋯ menu overlay and the one sheet.
struct BrowseStartView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Saved pages in no folder, newest first (the start page's Saved).
    @Query(LibraryQueries.loosePages(sort: .newest)) private var savedPages: [Page]
    /// Every saved page, for address suggestions.
    @Query(LibraryQueries.savedInLibrary) private var allSaved: [Page]
    @Query(LibraryQueries.recentlyPlayed) private var recentlyPlayed: [Page]
    @Query(LibraryQueries.undatedInProgress) private var undatedInProgress: [Page]
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    /// Once true, the browse WKWebView stays in the tree (history / back-forward). Starts false so
    /// cold launch on the start page never creates WebKit GPU/WebContent processes.
    @State private var browseWebViewMounted = false
    /// Address-bar dictation, made on the first mic tap.
    @State private var dictation: AddressDictation?
    @AppStorage(RecentSearches.storageKey) private var recentSearchesRaw = ""
    @State private var alertMessage: String?
    @State private var useFakeFailure = false
    /// A short message over the bottom chrome ("Nothing to listen to on this page").
    @State private var toast: String?

    private var webStore: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }

    /// Something covers the browser (the library, a sheet, Now Playing).
    private var isCovered: Bool {
        shell.isInLibrary || shell.reader != nil || shell.isNowPlayingPresented
    }

    /// The current page, when it is saved in the Library (⋯ → Save / Remove from Saved). Read
    /// when the menu opens.
    private var currentSavedPage: Page? {
        guard let url = webStore.currentURL, url.isWeb, let page = library.page(url: url),
              page.isSavedToLibrary else { return nil }
        return page
    }

    private var hasPage: Bool { webStore.hasPage }

    /// Create the browse WKWebView only after the first non-start navigation; keep it thereafter.
    private var showsBrowseWebView: Bool {
        browseWebViewMounted || hasPage
    }

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesRaw) }

    var body: some View {
        browser
            // Under the sheets the browser stays as it is (so pulling one down reveals it), but it
            // is out of reach until they are gone.
            .covered(isCovered)
            // While searching, avoid the keyboard so the field sits right above it. Otherwise keep
            // ignoring it (typing into a web page must not resize the page / the web view).
            .ignoresSafeArea(.keyboard, edges: search.isFocused ? [] : .bottom)
            // The reader and the library cover the whole browser, edge to edge. Outside the page
            // ZStack, whose `.clipped()` would cut them at the safe area.
            .overlay { layers }
            // Every surface's ⋯ menu: grows out of its button and covers it (Safari iOS 26), over
            // everything else (the library's navigation bar too).
            .overlay { menuOverlay }
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
            articles: allSaved,
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
            onListen: listen,
            onSubmit: { submit(search.text) },
            onMic: toggleDictation,
            onOpenLibrary: shell.openLibrary,
            menu: { .browse(browseMenu, perform: perform) }
        )
        .overlay(alignment: .top) { toastLayer }
    }

    private var menuOverlay: some View {
        MorphMenuOverlay(item: Binding(get: { shell.menu }, set: { shell.menu = $0 }),
                         anchor: shell.menuAnchor) { context, close in
            MoreMenuPanel(context: context, close: close)
        }
    }

    // MARK: - Layers

    /// The library, the Reader sheet over it (or over the browser), Now Playing over everything.
    /// Each layer is out of reach and hidden from VoiceOver while one covers it.
    private var layers: some View {
        ZStack {
            if shell.isInLibrary {
                LibrarySurface()
                    .covered(shell.reader != nil || shell.isNowPlayingPresented)
                    .transition(.opacity)
            }
            if let reader = shell.reader {
                ReaderSheetScreen(state: reader, speech: speech)
                    .id(reader.presentation)
                    .covered(shell.isNowPlayingPresented)
            }
            if shell.isNowPlayingPresented {
                NowPlayingScreen(speech: speech)
                    .id(shell.nowPlayingPresentation)
            }
        }
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast {
            Toast(message: toast, systemImage: "headphones")
                .padding(.horizontal, Spacing.pageMargin)
                // Its bottom edge a gap above the chrome's top.
                .alignmentGuide(.top) { $0[.bottom] + Spacing.xs }
                .transition(.opacity)
                .task {
                    try? await Task.sleep(for: Toast.duration)
                    withAnimation(Motion.snappy) { self.toast = nil }
                }
        }
    }

    // MARK: - 🎧

    /// 🎧: pause / resume when the page is what you hear; otherwise extract it and listen now.
    /// What's playing keeps playing until this page is ready; a page with nothing to listen to
    /// changes nothing and says so.
    private func listen() {
        guard let url = webStore.currentURL else { return }
        let target = ListenTarget.webPage(canonicalURL: ArticleIdentity.canonicalURLString(from: url))
        speech.press(target) {
            let page = page
            Task {
                if case .nothingToListenTo = await page.listenNow() {
                    withAnimation(Motion.snappy) { toast = "Nothing to listen to on this page" }
                }
            }
        }
    }

    // MARK: - ⋯ menu

    private var shareURL: URL? {
        webStore.currentURL.flatMap { $0.isWeb ? $0 : nil }
    }

    private var browseMenu: BrowseMenu {
        BrowseMenu(
            hasPage: hasPage,
            canOpenReader: canOpenReader,
            isSaved: currentSavedPage != nil,
            canSave: hasPage && shell.busy == nil,
            isBookmarked: currentBookmark != nil,
            canBookmark: webStore.currentURL.map(LibraryStore.canFavorite) ?? false,
            canShare: shareURL != nil,
            fakeExtractionFailure: speech.developerOptionsEnabled ? $useFakeFailure : nil
        )
    }

    private func perform(_ action: BrowseMenu.Action) {
        switch action {
        case .newSearch: shell.showStartPage()
        case .openReader: run { try await $0.openInReader() }
        case .toggleSave: toggleSave()
        case .toggleBookmark: run { page in await page.toggleBookmark() }
        case .bookmarks: shell.present(.bookmarks)
        case .reload: webStore.refresh()
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .voiceSettings: shell.present(.voiceSettings)
        case .saved: shell.openLibrary()
        case .history: shell.present(.history)
        }
    }

    private var canOpenReader: Bool { hasPage && webStore.isReaderable && shell.busy == nil }

    private var currentBookmark: Page? {
        library.favorite(for: webStore.currentURL)
    }

    // MARK: - Start page

    private var startPage: some View {
        FavoritesQuery(folderID: library.favorites().id) { favorites in
            BrowseStartPage(
                bookmarks: favorites,
                continueListening: LibraryQueries.continuePages(recent: recentlyPlayed, undated: undatedInProgress),
                saved: savedPages,
                recentSearches: recentSearches,
                onOpenBookmark: { if let url = $0.url { shell.navigate(to: url) } },
                onShowBookmarks: { shell.present(.bookmarks) },
                onDeleteBookmark: { library.removeFavorite($0) },
                onRenameBookmark: { library.renameFavorite($0, to: $1) },
                onOpenArticle: { shell.openSaved($0.listenKey, in: library) },
                onShowLibrary: shell.openLibrary,
                onSearch: submit,
                onClearSearches: { recentSearchesRaw = "" }
            )
            .task(id: favorites.count) { await library.backfillFavoriteIcons() }
        }
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
                           library: library, speech: speech, recentVisits: recentVisits)
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
        if let saved = currentSavedPage {
            ArticleSaveCoordinator(library: library, speech: speech)
                .unsave(key: saved.listenKey, canonicalURL: saved.canonicalURL ?? "")
        } else {
            run { try await $0.save() }
        }
    }
}

private extension View {
    /// A layer under another one: out of reach and hidden from VoiceOver. It stays in the tree, so
    /// its state survives.
    func covered(_ isCovered: Bool) -> some View {
        allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
    }
}
