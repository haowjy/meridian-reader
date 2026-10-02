import SwiftUI
import SwiftData
import WebKit

/// The browser, and the root of the shell: the web page or start page with its bottom chrome,
/// the address search layer, and over it whichever surface `ShellState` says is up (the ✕
/// reader or the library), the one ⋯ menu overlay and the one sheet.
struct BrowseStartView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.articleExtractor) private var extractor
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
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

    /// Saved articles in progress, most recently listened first.
    private var continueListeningArticles: [SavedArticle] {
        let candidates = articles.map { row in
            // Paragraph count only matters for pre-history saves (and decoding blocks isn't free).
            let needsCount = listenHistory.entry(for: row.id) == nil && row.playbackParagraphIndex > 0
            return ContinueListening.Candidate(
                id: row.id, savedAt: row.savedAt, paragraph: row.playbackParagraphIndex,
                utf16Offset: row.playbackUTF16Offset,
                paragraphCount: needsCount ? row.cachedListenParagraphs?.count : nil
            )
        }
        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ContinueListening.inProgress(candidates, history: listenHistory).compactMap { byID[$0.id] }
    }

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesRaw) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if showsBrowseWebView {
                    WebView(store: webStore, initialURL: nil)
                        .opacity(hasPage && !isReaderShown ? 1 : 0)
                        .allowsHitTesting(hasPage && !isReaderShown)
                        .onAppear { browseWebViewMounted = true }
                }

                if !hasPage && !isReaderShown {
                    startPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Safari-style search session: full-bleed Recent Searches / suggestions over the page.
            .overlay {
                if search.isActive && shell.isBrowsing {
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
            }
            .clipped()

            // The reader and the library draw their own chrome.
            if shell.isBrowsing {
                BrowserBottomChrome(
                    speech: speech,
                    dictation: dictation,
                    onOpenReader: { Task { await runReader() } },
                    onSubmit: { submit(search.text) },
                    onMic: toggleDictation,
                    onOpenLibrary: shell.openLibrary,
                    onOpenNowPlaying: {
                        if let id = speech.activeSessionID { shell.openNowPlaying(id, in: modelContext) }
                    },
                    menu: { .browse(browseMenu, perform: perform) }
                )
            }
        }
        // While searching, avoid the keyboard so the field sits right above it. Otherwise keep
        // ignoring it (typing into a web page must not resize the page / the web view).
        .ignoresSafeArea(.keyboard, edges: search.isFocused ? [] : .bottom)
        // Reader Mode covers the whole browser, edge to edge (the text runs under its bars). Outside
        // the page ZStack, whose `.clipped()` would cut it at the safe area.
        .overlay {
            if case .reader(let article, let origin) = shell.surface {
                readerOverlay(for: article, origin: origin)
                    .transition(.opacity)
            }
        }
        .overlay { libraryOverlay }
        // Every surface's ⋯ menu: grows out of its button and covers it (Safari iOS 26), over
        // everything else (the library's navigation bar too).
        .overlay {
            MorphMenuOverlay(item: Binding(get: { shell.menu }, set: { shell.menu = $0 }),
                             anchor: shell.menuAnchor) { context, close in
                MoreMenuPanel(context: context, close: close)
            }
        }
        .background {
            ListenHistoryRecorder(speech: speech) { activeID in
                listenHistory = ListenHistory(defaults: .standard)
                shell.noteActiveSession(activeID)
            }
        }
        .alert("Couldn’t extract", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            speech.onArticleFinished = { id in
                ListenHistory.record(id, finished: true)
            }
            openDemoReaderForUITestsIfRequested()
            openTestPagesIfRequested()
            openLibraryIfRequested()
            seedBookmarksIfRequested()
            await resumeAfterCrashIfNeeded()
        }
        .sheet(item: Binding(get: { shell.sheet }, set: { shell.sheet = $0 })) { sheet in
            sheetContent(sheet)
        }
        .alert("Dictation", isPresented: Binding(
            get: { dictation?.errorMessage != nil },
            set: { if !$0 { dictation?.errorMessage = nil } }
        )) {
            Button("Open Settings") {
                dictation?.errorMessage = nil
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { dictation?.errorMessage = nil }
        } message: {
            Text(dictation?.errorMessage ?? "")
        }
        .onChange(of: webStore.currentURL) { _, _ in shell.syncAddressField() }
        .onChange(of: webStore.isLoading) { _, loading in
            guard !loading else { return }
            Task { await recordRecentVisitIfNeeded() }
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

    // MARK: - Surfaces

    @ViewBuilder
    private var libraryOverlay: some View {
        if shell.isInLibrary {
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

    @ViewBuilder
    private func sheetContent(_ sheet: ShellSheet) -> some View {
        switch sheet {
        case .bookmarks:
            BookmarksListView(store: bookmarkStore) { bookmark in
                shell.sheet = nil
                if let url = bookmark.url { shell.navigate(to: url) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .history:
            BrowseHistoryView(visits: Array(recentVisits.prefix(RecentVisit.maxEntries))) { visit in
                shell.sheet = nil
                if let url = visit.url { shell.navigate(to: url) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .voiceSettings:
            NavigationStack {
                SpeechSettingsView(speech: speech)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { shell.sheet = nil }
                        }
                    }
            }
        case .share(let url):
            ActivityShareSheet(items: [url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    /// UI-test hook (`-openDemoInBrowseReader`, with `-seedDemoArticle`): show the seeded article
    /// in the ✕ Reader Mode without needing the network.
    private func openDemoReaderForUITestsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-openDemoInBrowseReader"),
              !isReaderShown, let row = articles.first else { return }
        var article = ReaderArticle(saved: row)
        if article.document.isEmpty {
            let doc = SavedArticle.buildListenDocument(plainText: row.plainText, cleanedHTML: row.cleanedHTML, title: row.title)
            article.document = doc
            article.trustedParagraphs = doc.paragraphs
        }
        shell.showReader(article, origin: .standalone)
    }

    /// UI-test hook (`-browseTestPages`): offline pages served by `TestPageSchemeHandler`, with a
    /// link to a second page, so ‹ / › state can be checked without the network.
    /// UI-test hook (`-openLibrary`): start with the library surface open (article-list tests).
    private func openLibraryIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("-openLibrary") { shell.openLibrary() }
    }

    private func openTestPagesIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-browseTestPages"), !hasPage,
              let url = URL(string: "reader-test://pages/one") else { return }
        webStore.load(url)
    }

    // MARK: - ⋯ menu

    private var shareURL: URL? {
        guard hasPage, let url = webStore.currentURL, url.isWeb else { return nil }
        return url
    }

    private var browseMenu: BrowseMenu {
        BrowseMenu(
            hasPage: hasPage,
            canOpenReader: canOpenReader,
            isSaved: currentSavedArticle != nil,
            canSave: hasPage && shell.busy == nil,
            isBookmarked: currentBookmark != nil,
            canBookmark: bookmarkableURL != nil,
            canShare: shareURL != nil,
            fakeExtractionFailure: speech.developerOptionsEnabled ? $useFakeFailure : nil
        )
    }

    private func perform(_ action: BrowseMenu.Action) {
        switch action {
        case .newSearch: shell.showStartPage()
        case .openReader: Task { await runReader() }
        case .toggleSave: Task { await toggleSaveFromBrowser() }
        case .toggleBookmark: Task { await toggleBookmark() }
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
        hasPage ? bookmarkStore.bookmark(for: webStore.currentURL) : nil
    }

    // MARK: - Start page

    private var startPage: some View {
        BrowseStartPage(
            bookmarks: bookmarkStore.bookmarks,
            continueListening: continueListeningArticles,
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
        .task(id: bookmarkStore.bookmarks.count) { await backfillBookmarkIcons() }
    }

    /// ⋯ → Bookmark / Remove Bookmark for the current page (URL, title, icon only).
    private var bookmarkableURL: URL? {
        guard hasPage, let url = webStore.currentURL, BookmarkStore.isBookmarkable(url) else { return nil }
        return url
    }

    @MainActor
    private func toggleBookmark() async {
        guard let url = bookmarkableURL else { return }
        if let existing = bookmarkStore.bookmark(for: url) {
            bookmarkStore.remove(id: existing.id)
            return
        }
        let liveTitle = webStore.webView?.title.flatMap { $0.isEmpty ? nil : $0 }
        let added = bookmarkStore.add(url: url, title: liveTitle ?? webStore.pageTitle,
                                      faviconData: recentFavicon(for: url))
        if !FaviconFetcher.isTileSized(added.faviconData), let icon = await fetchFavicon(for: url),
           added.faviconData == nil || FaviconFetcher.isTileSized(icon) {
            bookmarkStore.setFavicon(icon, for: added.id)
        }
    }

    /// Bookmarks without a tile-sized icon (seeded, or the page only had a 16 px favicon): try
    /// the site's icon once per launch. A smaller icon never replaces a usable one.
    /// Fetches run concurrently; a bookmark only counts as tried once its fetch finished, so a
    /// cancelled pass (the view went away, the list changed) retries next time.
    @MainActor
    private func backfillBookmarkIcons() async {
        let pending = bookmarkStore.bookmarks.filter {
            !FaviconFetcher.isTileSized($0.faviconData) && !Self.iconTried.contains($0.id)
        }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: (UUID, Data?).self) { group in
            for bookmark in pending {
                let host = bookmark.host
                group.addTask { (bookmark.id, await FaviconFetcher.fetch(forHost: host)) }
            }
            for await (id, icon) in group {
                guard !Task.isCancelled else { return }
                Self.iconTried.insert(id)
                guard let icon, let current = bookmarkStore.bookmarks.first(where: { $0.id == id }),
                      current.faviconData == nil || FaviconFetcher.isTileSized(icon) else { continue }
                bookmarkStore.setFavicon(icon, for: id)
            }
        }
    }

    @MainActor private static var iconTried = Set<UUID>()

    /// UI-test hooks: `-resetBookmarks` clears the bookmark store; `-seedBookmarks` also adds a few.
    private func seedBookmarksIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-resetBookmarks") || args.contains("-seedBookmarks") else { return }
        bookmarkStore.removeAll()
        guard args.contains("-seedBookmarks") else { return }
        let seeds: [(String, String)] = [
            ("https://www.gutenberg.org/", "Project Gutenberg"),
            ("https://en.wikipedia.org/wiki/Speech_synthesis", "Speech synthesis"),
            ("https://news.ycombinator.com/", "Hacker News"),
            ("https://www.theverge.com/", "The Verge"),
            ("https://example.com/", "Example"),
        ]
        for (url, title) in seeds {
            if let u = URL(string: url) { bookmarkStore.add(url: u, title: title, faviconData: nil) }
        }
    }

    /// Kokoro crashed last session: reopen the article at the paragraph that was playing — playing
    /// again (on the ONNX route, once it's loaded) if the crash just happened, else paused there.
    private func resumeAfterCrashIfNeeded() async {
        let tts = speech.localTTS
        // The target may predate paragraph layout v3; migrate first (no-op once done) so its
        // paragraph and the article's blocks use the same numbering.
        ArticleLibrary.migrateParagraphLayout(in: modelContext, localTTS: tts)
        guard let target = tts.takePendingResume() else { return }
        guard let article = articles.first(where: { target.matches($0.id) }) else {
            ListenTimingLog.log("kokoro_resume", ["ok": false, "why": "article not found", "key": String(target.articleKey.prefix(8))])
            return
        }
        let session = SpeechSession.saved(article)
        let p = min(max(0, target.paragraph), max(0, session.document.count - 1))
        article.playbackParagraphIndex = p
        shell.openSaved(article.id, in: modelContext)
        if target.autoPlay {
            // Wait (≤20 s) for the Kokoro host so the resume doesn't start on Apple.
            var waited = 0
            while !tts.usesLocalEngine, tts.pendingEngineID != nil, waited < 100 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
            speech.start(session, fromParagraph: p)
        } else {
            speech.prepare(session, startingParagraph: p)
        }
        ListenTimingLog.log("kokoro_resume", [
            "ok": true, "key": ListenTimingLog.shortKey(article.id), "p": p, "auto_play": target.autoPlay,
            "local": tts.usesLocalEngine,
        ])
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

    // MARK: - Recents

    @MainActor
    private func recordRecentVisitIfNeeded() async {
        guard let url = webStore.currentURL, url.isWeb else { return }
        var icon: Data?
        if let webView = webStore.webView {
            icon = await FaviconFetcher.fetch(from: webView)
        }
        if icon == nil, let host = url.host {
            icon = await FaviconFetcher.fetch(forHost: host)
        }
        RecentVisitRecorder.record(
            url: url,
            title: webStore.pageTitle,
            faviconData: icon,
            in: modelContext
        )
    }

    // MARK: - Extract / save

    private func activeExtractor() -> any ArticleExtracting {
        useFakeFailure ? FakeArticleExtractor(mode: .failure) : extractor
    }

    @MainActor
    private func makeContext() async throws -> ExtractionContext {
        guard let url = webStore.currentURL else {
            throw ExtractionError.unavailable(reason: "Open a page first.")
        }
        let html = try await webStore.snapshotHTML()
        return ExtractionContext(
            url: url,
            pageTitle: webStore.pageTitle,
            htmlSnapshot: html
        )
    }

    @MainActor
    private func runReader() async {
        shell.busy = .reader
        defer { shell.busy = nil }
        do {
            let context = try await makeContext()
            let extracted = try await activeExtractor().extract(from: context)
            // Identity v2: saved row for this canonical URL → its id/playhead/bookmark.fill,
            // else the URL-derived key. Same key on every reopen → cached audio is reused.
            var article = ArticleLibrary.readerArticle(url: context.url, extracted: extracted, in: modelContext)
            if article.faviconData == nil {
                article.faviconData = recentFavicon(for: context.url)
            }
            shell.showReader(article, origin: .page(context.url))
            if article.faviconData == nil {
                let icon = await fetchFavicon(for: context.url)
                shell.updateReader(id: article.id) { if $0.faviconData == nil { $0.faviconData = icon } }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Bottom-bar bookmark (web page, Reader hidden). Idempotent save / unsave by canonical URL.
    /// Reader Mode's own bookmark lives in `ArticleReaderScreen`.
    @MainActor
    private func toggleSaveFromBrowser() async {
        if let saved = currentSavedArticle {
            let id = saved.id
            let canonical = saved.canonicalURL
            ArticleLibrary.unsave(id: id, canonicalURL: canonical, in: modelContext)
            speech.localTTS.markListenCacheEphemeral(id, canonicalURL: canonical)
            return
        }
        shell.busy = .save
        defer { shell.busy = nil }
        do {
            let context = try await makeContext()
            let extracted = try await activeExtractor().extract(from: context)
            var article = ArticleLibrary.readerArticle(url: context.url, extracted: extracted, in: modelContext)
            article.faviconData = article.faviconData ?? recentFavicon(for: context.url)
            if article.faviconData == nil {
                article.faviconData = await fetchFavicon(for: context.url)
            }
            let row = ArticleLibrary.save(article, in: modelContext)
            speech.localTTS.prepareListenIdentity(
                key: row.id,
                paragraphs: article.document.paragraphs,
                trustedParagraphs: article.trustedParagraphs,
                legacyKeys: article.legacyCacheKeys,
                isLivePlayback: speech.activeSessionID == row.id
            )
            speech.localTTS.migrateListenCache(from: row.id, to: row.id)
            speech.localTTS.startBakeIfNeeded(
                articleID: row.id,
                paragraphs: article.document.paragraphs,
                voiceID: speech.cacheVoiceID
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func recentFavicon(for url: URL) -> Data? {
        guard let host = url.host else { return nil }
        let urlString = url.absoluteString
        return recentVisits.first(where: {
            $0.urlString == urlString || $0.host.caseInsensitiveCompare(host) == .orderedSame
        })?.faviconData
    }

    @MainActor
    private func fetchFavicon(for url: URL) async -> Data? {
        var icon: Data?
        if let webView = webStore.webView {
            icon = await FaviconFetcher.fetch(from: webView)
        }
        if icon == nil, let host = url.host {
            icon = await FaviconFetcher.fetch(forHost: host)
        }
        return icon
    }
}

/// Notes when listening starts (Continue listening order) without making the browser re-render
/// on every playhead tick: only this empty view observes the speech controller.
private struct ListenHistoryRecorder: View {
    @Bindable var speech: SpeechController
    /// Runs with the active session's id whenever it or its playing state changes.
    var onChange: (UUID?) -> Void

    private struct Key: Equatable {
        let id: UUID?
        let playing: Bool
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: Key(id: speech.activeSessionID, playing: speech.isPlaying)) { _, key in
                if let id = key.id, key.playing { ListenHistory.record(id) }
                onChange(key.id)
            }
    }
}
