import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WebKit

/// The browser, and the root of the shell: the web page or start page with its bottom chrome,
/// the address search layer, and over it the layers `ShellState` says are up, in order: the
/// library, the Reader sheet, Now Playing, the one ⋯ menu overlay and the one sheet.
struct BrowseStartView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(FollowCenter.self) private var follow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]
    /// The Favorites tiles' folder menus: their Rename and Delete questions.
    @State private var favoritesScreen = LibraryScreenState()

    /// Once true, the browse WKWebView stays in the tree (history / back-forward). Starts false so
    /// cold launch on the start page never creates WebKit GPU/WebContent processes.
    @State private var browseWebViewMounted = false
    /// Address-bar dictation, made on the first mic tap.
    @State private var dictation: AddressDictation?
    /// Measured height of the bottom chrome (SurfaceBand), used to keep reading sheets above it.
    @State private var chromeHeight: CGFloat = 0
    @AppStorage(RecentSearches.storageKey) private var recentSearchesRaw = ""
    @State private var alertMessage: String?
    @Environment(\.readingAppearance) private var readingAppearance

    private var webStore: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }

    /// The page content is behind a layer (library, reader, Now Playing): disable it.
    private var isPageCovered: Bool {
        shell.isInLibrary || shell.reader != nil || shell.isNowPlayingPresented
    }

    private var hasPage: Bool { webStore.hasPage }

    /// Create the browse WKWebView only after the first non-start navigation; keep it thereafter.
    private var showsBrowseWebView: Bool {
        browseWebViewMounted || hasPage
    }

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesRaw) }

    var body: some View {
        browser
            // While searching, avoid the keyboard so the field sits right above it. Otherwise keep
            // ignoring it (typing into a web page must not resize the page / the web view).
            .ignoresSafeArea(.keyboard, edges: search.isFocused ? [] : .bottom)
            // The library covers the whole browser (it draws its own chrome). Reader and Now
            // Playing stop above the chrome so it stays visible and usable (C140).
            .overlay { libraryLayer }
            .overlay { readingLayer }
            // Every surface's ⋯ menu: grows out of its button and covers it (Safari iOS 26), over
            // everything else (the library's navigation bar too).
            .overlay { menuOverlay }
            .sheet(item: Binding(get: { shell.sheet.flatMap { $0.coversTheScreen ? nil : $0 } }, set: { shell.sheet = $0 })) {
                ShellSheetView(sheet: $0)
            }
            .fullScreenCover(item: Binding(get: { shell.sheet.flatMap { $0.coversTheScreen ? $0 : nil } },
                                           set: { shell.sheet = $0 })) { ShellSheetView(sheet: $0) }
            // *Import Book…*: the picked book is copied in and imported (the import sheet).
            .fileImporter(isPresented: Binding(get: { shell.isPickingBook }, set: { shell.isPickingBook = $0 }),
                          allowedContentTypes: [.epub]) { result in
                guard case .success(let url) = result else { return }
                BookImportActions(library: library, shell: shell).importPicked(url, into: shell.bookPickDestination)
            }
            .modifier(BrowseAlerts(extractionError: $alertMessage, dictation: dictation))
            .onChange(of: webStore.currentURL) { _, _ in shell.browserPageChanged() }
            .onAppear { webStore.onBookDownload = bookDownloaded }
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
                if !focused { dictation?.stop() }
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
            // Page content is non-interactive while a layer covers it; the chrome stays reachable.
            .covered(isPageCovered)

            // Always present: the chrome height is measured here so reading sheets stop above it.
            // Hidden when the library is up (it draws its own chrome) but stays in layout.
            bottomChrome
                .opacity(shell.isInLibrary ? 0 : 1)
                .allowsHitTesting(!shell.isInLibrary)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
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
            isDictating: dictation?.isActive == true,
            onSubmit: submit,
            onClearRecentSearches: { recentSearchesRaw = "" }
        )
    }

    /// The page the browser shows, for 🔖 and ⋯: a web page (or a UI test's page); the start page
    /// is none.
    private var webPage: URL? { webStore.currentURL.flatMap { $0.isWebOrTestPage ? $0 : nil } }

    private var bottomChrome: some View {
        let canonical = webPage.map(ArticleIdentity.canonicalURLString(from:))
        return ArticleLookup(key: canonical.map { ArticleIdentity.articleKey(canonicalURL: $0) }, canonicalURL: canonical) { page in
            let actions = pageActions(page)
            BrowserBottomChrome(
                speech: speech,
                dictation: dictation,
                isSaved: actions.isSaved,
                onOpenReader: { run { try await $0.openInReader() } },
                onListen: listen,
                onSubmit: { submit(search.text) },
                onMic: toggleDictation,
                onToggleSave: actions.toggleSaved,
                onSaveToFolder: actions.saveToFolder,
                menu: { menu(actions) }
            )
        }
        .overlay(alignment: .top) { PrepareProgressEdge() }
        .overlay(alignment: .top) { ShellToastLayer() }
    }

    private var menuOverlay: some View {
        MorphMenuOverlay(item: Binding(get: { shell.menu }, set: { shell.menu = $0 }),
                         anchor: shell.menuAnchor,
                         readingPalette: { [readingAppearance] context in
                             context.isOnReadingPage ? readingAppearance.palette(accent: AppAppearance.shared.accent) : nil
                         }) { context, close in
            MoreMenuPanel(context: context, close: close)
        }
    }

    // MARK: - Layers

    /// The Library, covering the whole browser including the chrome (it has its own chrome).
    /// Out of reach while a reading sheet is over it.
    private var libraryLayer: some View {
        Group {
            if shell.isInLibrary {
                LibrarySurface()
                    .covered(shell.reader != nil || shell.isNowPlayingPresented)
                    .transition(.opacity)
            }
        }
    }

    /// The Reader sheet and Now Playing, constrained to stop above the bottom chrome so the
    /// chrome stays visible and usable. Clipped so the sheet's background never bleeds below.
    private var readingLayer: some View {
        VStack(spacing: 0) {
            ZStack {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // Transparent gap: lets the chrome show through; passes touches to the chrome below.
            Color.clear
                .frame(height: chromeHeight)
                .allowsHitTesting(false)
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
                    withAnimation(Motion.snappy) {
                        shell.showToast(ShellToast(message: String(localized: "Nothing to listen to on this page"),
                                                   systemImage: Icons.listen))
                    }
                }
            }
        }
    }

    // MARK: - ⋯ menu

    /// The page the browser shows, as every menu sees a page (`ArticleActions`): saved by extracting
    /// it first (⋯ spins), starred with the web view's title and icon.
    private func pageActions(_ libraryPage: Article?) -> ArticleActions {
        let service = page
        let loaded = ArticleActions.LoadedPage(canSave: hasPage && shell.busy == nil,
                                            save: { folder in run { try await $0.save(in: folder) } },
                                            toggleFavorite: service.toggleFavorite)
        return ArticleActions(article: libraryPage, url: webPage, loaded: webPage == nil ? nil : loaded, library: library,
                           shell: shell, speech: speech, preparedAudio: preparedAudio, follow: follow)
    }

    /// The browser's ⋯: the page's menu (`ArticleMenu`) while a page is up, then *Follow…*,
    /// *Reload*, *Prepared Audio*, then `[Settings][Saved][Reader]` (C140).
    private func menu(_ actions: ArticleActions) -> MenuContext {
        var facts = MenuRegistry.Facts()
        facts.canFollow = webStore.currentURL?.isWebOrTestPage == true
        facts.hasWebPage = hasPage
        // No *New Search*: a tap on the address field starts one (C98).
        let screen = MenuContext.screenRows(at: .browser, facts: facts, shell: shell) { option in
            switch option {
            case .follow:
                return MenuRow(id: "moreFollow", title: Verbs.follow, icon: Icons.follow) {
                    guard let url = webStore.currentURL else { return }
                    shell.present(.follow(FollowFlow(url: url, parentID: nil, center: follow)))
                }
            case .reload:
                return MenuRow(id: "moreReload", title: Verbs.reload, icon: Icons.reload, action: webStore.refresh)
            default: return nil
            }
        }
        let reader = MenuRow(id: "moreReaderToggle", title: Verbs.reader, icon: Icons.reader,
                             availability: MenuAvailability(when: canOpenReader),
                             accessibilityHint: Verbs.openInReader) { run { try await $0.openInReader() } }
        return MenuContext(item: webPage == nil ? [] : ArticleMenu(actions: actions, place: .browser).rows, screen: screen,
                           tiles: MenuContext.tiles(shell, last: reader))
    }

    private var canOpenReader: Bool { hasPage && webStore.isReaderable && shell.busy == nil }

    // MARK: - Start page

    private var startPage: some View {
        FavoritesQuery { favorites, folders in
            BrowseStartPage(
                favorites: favorites,
                favoriteFolders: folders,
                recentSearches: recentSearches,
                onOpenFavorite: { LibraryActions(library: library, speech: speech, shell: shell, follow: follow).open($0) },
                onOpenFavoriteFolder: { shell.showLibrary(at: library.path(to: $0)) },
                onShowFavorites: shell.showFavorites,
                pageMenu: { page in
                    AnyView(ArticleMenu(actions: ArticleActions(article: page, library: library, shell: shell, speech: speech,
                                                          preparedAudio: preparedAudio, follow: follow),
                                     place: .elsewhere))
                },
                folderMenu: { folder, onTurnOffPrepare in
                    AnyView(FolderMenu(folder: folder, articles: folder.playOrder,
                                       actions: LibraryActions(library: library, speech: speech, shell: shell, follow: follow),
                                       preparedAudio: preparedAudio, screen: favoritesScreen, place: .tile,
                                       onTurnOffPrepare: onTurnOffPrepare))
                },
                onSearch: submit,
                onClearSearches: { recentSearchesRaw = "" }
            )
            .task(id: favorites.count) { await library.backfillFavoriteIcons() }
            // A folder tile's Rename… and Delete Folder… ask here, as the Library's do there.
            .libraryDialogs(favoritesScreen) {}
        }
    }

    // MARK: - Address

    /// Submitted address field, recent search or suggestion: remember a search term, then load.
    private func submit(_ text: String) {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = BrowseURLParser.destination(from: raw) else { return }
        if BrowseURLParser.isSearch(raw) {
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

    /// The loaded page as an article.
    private var page: PageArticleService {
        PageArticleService(shell: shell, extractor: extractor, library: library, speech: speech,
                           recentVisits: recentVisits)
    }

    /// Runs a page action; a failed extraction shows the alert.
    /// A tapped `.epub` link prepared audio instead of showing; the book then waits in the import
    /// sheet for *Import*.
    private func bookDownloaded(_ event: WebViewStore.BookDownload) {
        switch event {
        case .started(let name):
            shell.showToast(ShellToast(message: String(localized: "Downloading “\(name)”…"), systemImage: Icons.prepare))
        case .finished(let file):
            BookImportActions(library: library, shell: shell).importPrepared(file)
        case .failed(let name):
            shell.showToast(ShellToast(message: String(localized: "Couldn't download “\(name)”"),
                                       systemImage: Icons.warning))
        }
    }

    private func run(_ action: @escaping (PageArticleService) async throws -> Void) {
        let page = page
        Task {
            do { try await action(page) } catch { alertMessage = error.localizedDescription }
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
