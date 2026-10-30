import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WebKit

/// The browser, and the root of the shell: the web page or start page with its bottom chrome,
/// the address search layer, and over it the layers `ShellState` says are up, in order: the
/// library, the Reader, Now Playing, the one ⋯ menu overlay and the one sheet.
struct BrowseStartView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(FollowCenter.self) private var follow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]
    /// Once true, the browse WKWebView stays in the tree (history / back-forward). Starts false so
    /// cold launch on the start page never creates WebKit GPU/WebContent processes.
    @State private var browseWebViewMounted = false
    /// Address-bar dictation, made on the first mic tap.
    @State private var dictation: AddressDictation?
    @AppStorage(RecentSearches.storageKey) private var recentSearchesRaw = ""
    @State private var alertMessage: String?
    @Environment(\.readingAppearance) private var readingAppearance
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The Library's screen state, shared by its screens and the bottom chrome (which the shell owns).
    @State private var libraryScreen = LibraryScreenState()
    /// The Library ⋯'s *Turn Off Prepare* asked: the question shows by the ⋯.
    @State private var turningOff: Folder?
    @AppStorage(LibraryTopLevel.sortKey) private var topLevelSort = LibraryTopLevel.defaultSort.rawValue

    private var webStore: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }

    /// Something covers the browser (the library, a sheet, Now Playing).
    private var isCovered: Bool {
        shell.isInLibrary || shell.reader != nil || shell.isNowPlayingPresented
    }

    private var hasPage: Bool { webStore.hasPage }

    /// What the chrome covers at the bottom of the page, from the screen's edge: two rows, one row or the
    /// strip as it folds (a step at a time, as drawn), one row
    /// while a search is open (the field's), nothing at regular width, where the chrome has its own bar below the page.
    private var obscuredBottom: CGFloat {
        guard !isRegular else { return 0 }
        if search.isActive { return ChromeMetrics.collapsedFootprint }
        return ChromeMetrics.footprint(step: shell.chromeScroll.drawnStep)
    }

    /// Create the browse WKWebView only after the first non-start navigation; keep it thereafter.
    private var showsBrowseWebView: Bool {
        browseWebViewMounted || hasPage
    }

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesRaw) }

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        regularShell(browser)
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
            .sheet(item: Binding(get: { shell.sheet.flatMap { $0.coversTheScreen ? nil : $0 } }, set: { shell.sheet = $0 })) {
                ShellSheetView(sheet: $0)
            }
            .fullScreenCover(item: Binding(get: { shell.sheet.flatMap { $0.coversTheScreen ? $0 : nil } },
                                           set: { shell.sheet = $0 })) { ShellSheetView(sheet: $0) }
            // *Import from…*: the picked EPUB/PDF is copied in and imported (the import sheet).
            .fileImporter(isPresented: Binding(get: { shell.isPickingBook }, set: { shell.isPickingBook = $0 }),
                          allowedContentTypes: [.epub, .pdf]) { result in
                guard case .success(let url) = result else { return }
                BookImportActions(library: library, shell: shell).importPicked(url, into: shell.bookPickDestination)
            }
            .modifier(BrowseAlerts(extractionError: $alertMessage, dictation: dictation))
            .onChange(of: webStore.currentURL) { _, _ in shell.browserPageChanged() }
            .onAppear { webStore.onBookDownload = bookDownloaded }
            .onChange(of: webStore.isLoading) { _, loading in
                guard !loading else { return }
                run { await $0.recordVisit() }
                reenterReaderIfAsked()
            }
            .onChange(of: webStore.isReaderable) { _, _ in reenterReaderIfAsked() }
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

    /// The page (or start page), the search layer over it, and at regular width the bottom chrome.
    /// Compact width draws the chrome in `layers`, over the page and the Library alike.
    private var browser: some View {
        VStack(spacing: 0) {
            ZStack {
                // The page runs under the chrome, through the bottom safe area, and keeps its last
                // line clear of the chrome by an inset.
                ZStack {
                    if showsBrowseWebView {
                        WebView(store: webStore,
                                bottomInset: isRegular ? 0 : ChromeHome.above(ChromeMetrics.footprint),
                                obscuredBottom: obscuredBottom,
                                onScroll: isRegular ? nil : { [chrome = shell.chromeScroll] in chrome.scrolled(to: $0) })
                            .opacity(hasPage ? 1 : 0)
                            // Under the in-place reader the page is neither touched nor read aloud.
                            .allowsHitTesting(hasPage && shell.pageReader == nil)
                            .accessibilityHidden(shell.pageReader != nil)
                            .onAppear { browseWebViewMounted = true }
                    }

                    if !hasPage {
                        startPage
                    }

                    if let article = shell.pageReader, !isRegular {
                        ReaderSurface(article: article, speech: speech, covered: isCovered,
                                      onEdgeSwipeBack: webStore.canGoBack ? goBack : nil)
                            .id(article.id)
                    }
                }
                .ignoresSafeArea(.container, edges: isRegular ? [] : .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Safari-style search session: full-bleed Recent Searches / suggestions over the page.
            .overlay {
                if search.isActive && shell.isBrowsing {
                    ZStack {
                        // Opaque to the bottom edge, behind the field and the keyboard: the list stops above
                        // the chrome's row, but the page must never show through the strip under it.
                        Palette.paper.ignoresSafeArea(edges: .bottom)
                        searchLayer
                            .padding(.bottom, isRegular ? 0 : ChromeHome.above(ChromeMetrics.collapsedFootprint))
                    }
                }
            }
            .clipped()

            // The library draws its own chrome and covers this; the reader overlay draws its own
            // too, but this stays under it so its pull-down reveals the browser whole.
            if isRegular && !shell.isInLibrary {
                bottomChrome
            }
        }
        // The page area is clipped to the safe area; what shows there (paper on the start page and
        // the search layer, the in-place reader's theme, a web page's own background) continues
        // up under the status bar.
        .background {
            if !hasPage || search.isActive {
                Palette.paper.ignoresSafeArea()
            } else if shell.pageReader != nil && !isRegular {
                readingAppearance.palette(accent: AppAppearance.shared.accent).background.ignoresSafeArea()
            } else if let page = webStore.pageBackground {
                Color(uiColor: page).ignoresSafeArea()
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

    /// The page the browser shows, for 🔖 and ⋯: a web page (or a Debug `reader-test://` page); the start page
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


    /// Regular width: persistent ~280 pt sidebar + main pane. Compact is unchanged.
    @ViewBuilder
    private func regularShell<Content: View>(_ content: Content) -> some View {
        if isRegular {
            HStack(spacing: 0) {
                if !shell.sidebarCollapsed {
                    RegularShellSidebar()
                }
                ZStack(alignment: .topLeading) {
                    content
                    if shell.sidebarCollapsed {
                        RegularSidebarRevealButton()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            content
        }
    }

    // MARK: - Layers

    /// The library, the Reader over it (or over the browser), Now Playing over them, and at
    /// compact width the bottom chrome over all of them. On compact width the Reader and Now Playing
    /// are destinations drawn in place under the chrome and cross-fade with the others; on regular
    /// width they are sheets that rise. Each layer is out of reach and hidden from VoiceOver while one covers it.
    private var layers: some View {
        ZStack {
            if shell.isInLibrary {
                LibrarySurface(chrome: libraryChrome)
                    .covered(shell.reader != nil || shell.isNowPlayingPresented || shell.libraryReader != nil)
                    .transition(.opacity)
                // Library Read: the page's text in place of the Library, which stays under it as it was.
                if let article = shell.libraryReader, !isRegular {
                    ReaderSurface(article: article, speech: speech,
                                  covered: shell.reader != nil || shell.isNowPlayingPresented,
                                  onEdgeSwipeBack: shell.closeLibraryReader)
                        .id(article.id)
                        .covered(shell.reader != nil || shell.isNowPlayingPresented)
                        .transition(.opacity)
                }
            }
            if let reader = shell.reader {
                ReaderSheetScreen(state: reader, speech: speech)
                    .id(reader.presentation)
                    .covered(shell.isNowPlayingPresented)
                    .transition(.opacity)
            }
            if shell.isNowPlayingPresented {
                NowPlayingScreen(speech: speech)
                    .id(shell.nowPlayingPresentation)
                    .transition(.opacity)
            }
        }
        .animation(isRegular || reduceMotion ? nil : Motion.snappy, value: ReadingLayers(reader: shell.reader?.presentation,
                                                                              nowPlaying: shell.nowPlayingPresentation,
                                                                              libraryReader: shell.libraryReader != nil))
        .onChange(of: isRegular, initial: true) { _, regular in shell.readsInPlace = !regular }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Listen's ‹ (compact): back to where the listening was launched from (kept across relaunches),
        // named ("‹ reddit.com", "‹ Tides"). Not in full screen, and not when there is nowhere to go.
        .overlay(alignment: .topLeading) {
            if !isRegular, let origin = shell.listenBackOrigin, !shell.chromeScroll.fullScreen {
                ListenBackButton(place: placeName(origin)) {
                    shell.backFromListen(folderExists: { library.folder(id: $0) != nil },
                                         article: { library.article(key: $0).map(ReaderArticle.init(article:)) })
                }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.snappy, value: shell.chromeScroll.fullScreen)
        // Compact: the one bottom chrome, over the browser, the Library, the Reader and Now
        // Playing alike. The Reader is a destination: it keeps the pill (row 2) under its text, and
        // the Reader or Now Playing hands the chrome the card it draws above it.
        .overlayPreferenceValue(ChromeCardKey.self) { card in
            if !isRegular {
                compactChrome(card)
            }
        }
    }

    /// ‹'s short name for a place: the Library folder's name (its nearest surviving one, else
    /// "Library"), or the page's site without "www.".
    private func placeName(_ origin: ListenOrigin) -> String {
        switch origin {
        case .library(let path):
            let kept = ShellState.surviving(path, exists: { library.folder(id: $0) != nil })
            if case .folder(let id)? = kept.last, let name = library.folder(id: id)?.name, !name.isEmpty { return name }
            return Verbs.library
        case .browser(let url):
            let host = url.host() ?? url.absoluteString
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    /// Which reading layers are up: a change cross-fades them on compact width.
    private struct ReadingLayers: Equatable {
        var reader: UUID?
        var nowPlaying: UUID?
        var libraryReader: Bool
    }

    // MARK: - Compact bottom chrome

    private var libraryChrome: LibraryChrome {
        LibraryChrome(shell: shell, library: library, speech: speech, preparedAudio: preparedAudio, screen: libraryScreen,
                      topLevelSort: $topLevelSort, turningOff: $turningOff)
    }

    /// The host for the browser's and the Library's chrome. The browser's depends on the page
    /// (saved or not), so the host sits inside its lookup.
    private func compactChrome(_ card: ChromeCard?) -> some View {
        let canonical = webPage.map(ArticleIdentity.canonicalURLString(from:))
        return ArticleLookup(key: canonical.map { ArticleIdentity.articleKey(canonicalURL: $0) }, canonicalURL: canonical) { page in
            ChromeHost(browse: browseChromeScreen(page), library: libraryChrome.chromeScreen(), card: card)
                .environment(libraryScreen)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func browseChromeScreen(_ libraryPage: Article?) -> ChromeScreen {
        let actions = pageActions(libraryPage)
        let search = search
        return ChromeScreen(
            session: search,
            cancelID: "addressCancel",
            onCancel: shell.endAddressSearch,
            // Like Safari: the session starts with the page's full address, selected.
            begin: { [webStore] in search.begin(with: webStore.currentURL?.absoluteString ?? "") },
            canGoBack: webStore.canGoBack,
            canGoForward: webStore.canGoForward,
            backID: "browseBack",
            forwardID: "browseForward",
            onBack: goBack,
            onForward: goForward,
            field: { focus in
                AnyView(BrowseAddressField(speech: speech, dictation: dictation,
                                           onOpenReader: { run { try await $0.openInReader(inPlace: true) } }, compact: true,
                                           onReload: reloadOrStop,
                                           onSubmit: { submit(search.text) }, onMic: toggleDictation, focus: focus))
            },
            more: AnyView(MoreMenuButton(id: "browseMore", chrome: true) { menu(actions) }),
            listen: shell.pageReader.map { AnyView(ReaderListenButton(article: $0)) },
            stripTitle: stripTitle
        )
    }

    /// What the folded chrome's strip names: the page's domain (no `www.`, no path), or in reader mode its source.
    private var stripTitle: String {
        let host = shell.pageReader?.sourceLabel ?? webStore.currentURL?.host() ?? ""
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return name.isEmpty ? String(localized: "Browser") : name
    }

    // MARK: - ‹ ›

    /// ‹: the previous page; the reader view it leaves comes back with ›.
    private func goBack() {
        shell.browserWillGoBack()
        webStore.goBack()
    }

    /// ›: the next page, in reader view again when ‹ left it from there.
    private func goForward() {
        shell.browserWillGoForward()
        webStore.goForward()
    }

    private func reenterReaderIfAsked() {
        guard shell.takeReaderToReenter() else { return }
        run { try await $0.openInReader(inPlace: true) }
    }

    // MARK: - ↻

    /// A reload brings the page back as the page.
    private func reload() {
        shell.closePageReader()
        webStore.refresh()
    }

    /// ↻ reloads the page; ✕ (while it loads) stops it.
    private func reloadOrStop() {
        if webStore.isLoading { webStore.stopLoading() } else { reload() }
    }

    // MARK: - 🎧

    /// 🎧 (regular width): pause / resume when the page is what you hear; otherwise extract it and listen now.
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

    /// The browser's ⋯: the page's menu (`ArticleMenu`) while a page is up, then *New Search*,
    /// *Text Appearance* (in reader mode), *Follow…*, *Reload*, *Prepared audio*, *Settings*, then
    /// `[Favorites][History][Reader]`.
    private func menu(_ actions: ArticleActions) -> MenuContext {
        var facts = MenuRegistry.Facts()
        facts.canFollow = webStore.currentURL?.isWebOrTestPage == true
        facts.hasWebPage = hasPage
        facts.inReaderMode = shell.pageReader != nil
        // No *New Search*: a tap on the address field starts one (C98).
        let screen = MenuContext.screenRows(at: .browser, facts: facts, shell: shell) { option in
            switch option {
            case .follow:
                return MenuRow(id: "moreFollow", title: Verbs.follow, icon: Icons.follow) {
                    guard let url = webStore.currentURL else { return }
                    shell.present(.follow(FollowFlow(url: url, parentID: nil, center: follow)))
                }
            case .textAppearance:
                return MenuRow(id: "moreTextAppearance", title: Verbs.textAppearance, icon: Icons.textAppearance) {
                    shell.readerAppearanceOpen = true
                }
            case .reload:
                return MenuRow(id: "moreReload", title: Verbs.reload, icon: Icons.reload, action: reload)
            default: return nil
            }
        }
        let showing = shell.pageReader != nil
        let reader = MenuRow(id: "moreReaderToggle", title: showing ? Verbs.showWebPage : Verbs.reader,
                             icon: showing ? Icons.readerShowing : Icons.reader,
                             availability: MenuAvailability(when: canOpenReader),
                             accessibilityHint: showing ? nil : Verbs.openInReader) { run { try await $0.openInReader(inPlace: !isRegular) } }
        return MenuContext(item: webPage == nil ? [] : ArticleMenu(actions: actions, place: .browser).rows, screen: screen,
                           tiles: MenuContext.tiles(shell, compact: !isRegular, last: reader), isOnReadingPage: showing)
    }

    private var canOpenReader: Bool { hasPage && webStore.isReaderable && shell.busy == nil }

    // MARK: - Start page

    private var startPage: some View {
        FavoritesQuery { favorites in
            BrowseStartPage(
                favorites: favorites,
                recentSearches: recentSearches,
                // Browse Favorites: open the page's own http(s) URL in the browser, not Reader.
                onOpenFavorite: { article in
                    if let url = article.url { shell.navigate(to: url) }
                },
                onShowFavorites: shell.showFavorites,
                pageMenu: { page in
                    AnyView(ArticleMenu(actions: ArticleActions(article: page, library: library, shell: shell, speech: speech,
                                                          preparedAudio: preparedAudio, follow: follow),
                                     place: .elsewhere))
                },
                onSearch: submit,
                onClearSearches: { recentSearchesRaw = "" }
            )
            .task(id: favorites.count) { await library.backfillFavoriteIcons() }
        }
        .modifier(CompactChromeInsets(isCompact: !isRegular))
        .modifier(CompactChromeScroll(isCompact: !isRegular))
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
