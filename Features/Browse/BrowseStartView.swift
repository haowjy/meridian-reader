import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WebKit

/// The browser, and the root of the shell: the web page or start page with its bottom chrome,
/// the address search layer, and over it the layers `ShellState` says are up, in order: the
/// library, the Reader sheet, Now Playing, the one ⋯ menu overlay and the one sheet; the shell's
/// prompt ("Move it to Favorites?") over all of them.
struct BrowseStartView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Every saved page, for address suggestions.
    @Query(LibraryQueries.savedInLibrary) private var allSaved: [Page]
    @Query(sort: \RecentVisit.visitedAt, order: .reverse) private var recentVisits: [RecentVisit]

    /// Once true, the browse WKWebView stays in the tree (history / back-forward). Starts false so
    /// cold launch on the start page never creates WebKit GPU/WebContent processes.
    @State private var browseWebViewMounted = false
    /// Address-bar dictation, made on the first mic tap.
    @State private var dictation: AddressDictation?
    @AppStorage(RecentSearches.storageKey) private var recentSearchesRaw = ""
    @State private var alertMessage: String?
    @State private var useFakeFailure = false

    private var webStore: WebViewStore { shell.web }
    private var search: SearchSession { shell.addressSearch }

    /// Something covers the browser (the library, a sheet, Now Playing).
    private var isCovered: Bool {
        shell.isInLibrary || shell.reader != nil || shell.isNowPlayingPresented
    }

    /// The current page, when it is saved in the Library (⋯ → Save to Library… / Remove from
    /// Library). Read when the menu opens.
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
            // *Import Book…*: the picked book is copied in and imported (the import sheet).
            .fileImporter(isPresented: Binding(get: { shell.isPickingBook }, set: { shell.isPickingBook = $0 }),
                          allowedContentTypes: [.epub]) { result in
                guard case .success(let url) = result else { return }
                BookImportActions(library: library, shell: shell).importPicked(url, into: shell.bookPickDestination)
            }
            // The ⋯ Debug row (Reader, Now Playing, Library) and long-press ▶: over every layer.
            // A shell sheet with a Debug entry hosts its own.
            .listenDebugSheet(speech, hosts: shell.sheet == nil)
            .alert(shell.prompt?.title ?? "", isPresented: Binding(get: { shell.prompt != nil },
                                                                    set: { if !$0 { shell.prompt = nil } }),
                   presenting: shell.prompt) { prompt in
                Button("Cancel", role: .cancel) { shell.prompt = nil }
                Button(prompt.confirmTitle) {
                    shell.prompt = nil
                    prompt.confirm()
                }
                .accessibilityIdentifier("promptConfirm")
            } message: { prompt in
                if let message = prompt.message { Text(message) }
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
        .overlay(alignment: .top) { DownloadProgressEdge() }
        .overlay(alignment: .top) { ShellToastLayer() }
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
                                                   systemImage: "headphones"))
                    }
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
            isFavorite: library.favorite(for: webStore.currentURL) != nil,
            canFavorite: webStore.currentURL.map(LibraryStore.canFavorite) ?? false,
            canShare: shareURL != nil,
            fakeExtractionFailure: speech.developerOptionsEnabled ? $useFakeFailure : nil
        )
    }

    private func perform(_ action: BrowseMenu.Action) {
        switch action {
        case .newSearch: shell.showStartPage()
        case .openReader: run { try await $0.openInReader() }
        case .saveToLibrary: saveToLibrary()
        case .removeFromLibrary: removeFromLibrary()
        case .toggleFavorite: page.toggleFavorite()
        case .favorites: shell.present(.favorites())
        case .reload: webStore.refresh()
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .voiceSettings: shell.present(.voiceSettings)
        case .downloads: shell.present(.downloads)
        case .history: shell.present(.history)
        }
    }

    private var canOpenReader: Bool { hasPage && webStore.isReaderable && shell.busy == nil }

    // MARK: - Start page

    private var startPage: some View {
        FavoritesQuery(folder: library.favorites()) { favorites, folders in
            BrowseStartPage(
                favorites: favorites,
                favoriteFolders: folders,
                recentSearches: recentSearches,
                onOpenFavorite: { LibraryActions(library: library, speech: speech, shell: shell).open($0) },
                onOpenFavoriteFolder: { shell.present(.favorites(folder: $0.id)) },
                onShowFavorites: { shell.present(.favorites()) },
                onRemoveFavorite: { page in
                    shell.attempt(String(localized: "Couldn’t remove from Favorites")) { try library.removeFavorite(page) }
                },
                onRenameFavorite: { page, title in
                    shell.attempt(String(localized: "Couldn’t rename")) { try library.renameFavorite(page, to: title) }
                },
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
    /// A tapped `.epub` link downloads instead of showing; the book then waits in the import
    /// sheet for *Import*.
    private func bookDownloaded(_ event: WebViewStore.BookDownload) {
        switch event {
        case .started(let name):
            shell.showToast(ShellToast(message: String(localized: "Downloading “\(name)”…"), systemImage: "arrow.down.circle"))
        case .finished(let file):
            BookImportActions(library: library, shell: shell).importDownloaded(file)
        case .failed(let name):
            shell.showToast(ShellToast(message: String(localized: "Couldn't download “\(name)”"),
                                       systemImage: "exclamationmark.triangle"))
        }
    }

    private func run(_ action: @escaping (PageArticleService) async throws -> Void) {
        let page = page
        Task {
            do { try await action(page) } catch { alertMessage = error.localizedDescription }
        }
    }

    /// ⋯ → Save to Library…: the Move tree, then the page is saved into the folder picked. The
    /// tree closes on the pick, as the page is extracted first; ⋯ spins, and a save that can't
    /// be stored says so in a toast over the browser.
    private func saveToLibrary() {
        FavoriteFlow(library: library, shell: shell).saveToFolder(title: String(localized: "Save to…"), current: nil) { folder in
            run { try await $0.save(in: folder) }
            return true
        }
    }

    /// ⋯ → Remove from Library, by canonical URL.
    private func removeFromLibrary() {
        guard let saved = currentSavedPage else { return }
        shell.attempt(String(localized: "Couldn’t remove from Library")) {
            try ArticleSaveCoordinator(library: library, speech: speech)
                .unsave(key: saved.listenKey, canonicalURL: saved.canonicalURL ?? "")
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
