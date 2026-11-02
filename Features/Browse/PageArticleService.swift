import Foundation

/// What the browser does with the page it has loaded: show it in the Reader, listen to it, save
/// it, record it in History. Extraction resolves the article's identity against the
/// library, so the same page gets the same key (and its cached audio) every time.
@MainActor
struct PageArticleService {
    let shell: ShellState
    let extractor: any ArticleExtracting
    let library: LibraryStore
    let speech: SpeechController
    /// Recently visited pages: their icon stands in until the page's own is fetched.
    let recentVisits: [RecentVisit]

    private var web: WebViewStore { shell.web }

    /// Address-bar reader icon / ⋯ → Reader: the page in the Reader sheet (Now Playing when it is
    /// the page you hear). The reader icon spins meanwhile. `inPlace` (compact width) is Safari's
    /// Reader instead: the page's text replaces the page, and the same call puts the page back.
    func openInReader(inPlace: Bool = false) async throws {
        if inPlace, shell.pageReader != nil { return shell.closePageReader() }
        shell.busy = .reader
        defer { shell.busy = nil }
        let epoch = shell.pageReaderEpoch
        let (article, url) = try await extract()
        if inPlace {
            // The page moved on while it was read: its text is no longer this page's.
            guard web.currentURL == url else { return }
            shell.openPageReader(article, requestedAt: epoch)
        } else {
            shell.openReader(article)
        }
        if article.artwork == nil {
            let icon = await favicon(for: url)
            shell.updateReader(id: article.id) { if $0.artwork == nil { $0.artwork = icon } }
        }
    }

    /// 🎧: listen to the page now. 🎧 spins while the page is extracted, and what's playing keeps
    /// playing; it is replaced only once this page has something to say, and only if nothing
    /// else was asked for meanwhile (`listen(toPageAt:…)`).
    func listenNow() async -> ListenNowOutcome {
        guard let url = web.currentURL else { return .nothingToListenTo }
        let outcome = await Self.listen(toPageAt: url, speech: speech, library: library) {
            try await extract().article
        }
        if case .started(let article) = outcome, article.artwork == nil, let icon = await favicon(for: url) {
            speech.setArtwork(icon, for: article.id)
        }
        return outcome
    }

    /// 🎧's decision, apart from the web view: begin a preparation request for the page at `url`,
    /// run `extract`, then start the article only while that request is still current. Stop
    /// Listening, another ▶ or another 🎧 during extraction supersedes it, and it starts nothing.
    static func listen(toPageAt url: URL, speech: SpeechController, library: LibraryStore,
                       extract: () async throws -> ReaderArticle) async -> ListenNowOutcome {
        let request = speech.beginPreparing(.webPage(canonicalURL: ArticleIdentity.canonicalURLString(from: url)))
        let article = try? await extract()
        guard speech.isStillPreparing(request) else { return .superseded }
        guard let article, ListeningTime.hasEnoughToListen(article.document) else {
            speech.endPreparing(request)
            return .nothingToListenTo
        }
        // The page's spot, when the library has it (saved, or played without saving); a page
        // heard to the end starts again from the top, as the Reader's Listen Again does.
        let page = library.article(key: article.id, canonicalURL: article.origin.canonicalURL)
        speech.localTTS.prepareListenIdentity(key: article.id, paragraphs: article.document.paragraphs,
                                              trustedParagraphs: article.trustedParagraphs,
                                              legacyKeys: article.legacyCacheKeys, isLivePlayback: false)
        speech.listen(to: article, at: page?.listenStart ?? .top)
        return .started(article)
    }

    /// The browser's page saved (`ArticleActions.LoadedPage.save`: *Save to Library* and Follow's
    /// *Save This Page Only* keep a page the Library has where it is; *Save to Folder…* files it in
    /// the folder picked in the Move tree). ⋯ spins meanwhile. It throws when the page can't be
    /// extracted or stored, and stores nothing once its task is cancelled (Follow's ✕).
    func save(_ placement: SavePlacement, expectedURL: URL?) async throws {
        guard web.currentURL == expectedURL else {
            throw ExtractionError.unavailable(reason: String(localized: "The page has changed. Open it again to save it."))
        }
        shell.busy = .save
        defer { shell.busy = nil }
        var (article, url) = try await extract()
        if article.artwork == nil {
            article.artwork = await favicon(for: url)
        }
        guard url == expectedURL, web.currentURL == expectedURL else {
            throw ExtractionError.unavailable(reason: String(localized: "The page has changed. Open it again to save it."))
        }
        try Task.checkCancellation()
        try ArticleSaveCoordinator(library: library, speech: speech).save(article, placement: placement)
    }

    /// The page finished loading: add it to History with its icon.
    func recordVisit() async {
        guard let url = web.currentURL, url.isWeb else { return }
        let icon = await favicon(for: url)
        library.recordVisit(url: url, title: web.pageTitle, faviconData: icon)
    }

    // MARK: - Pieces

    private func extract() async throws -> (article: ReaderArticle, page: URL) {
        guard let url = web.currentURL else {
            throw ExtractionError.unavailable(reason: "Open a page first.")
        }
        let source = SingleWebPageSource(url: url, htmlSnapshot: try await web.snapshotHTML(), extractor: extractor)
        let content = try await source.content(of: source.article)
        var article = library.readerArticle(url: url, extracted: content.extracted, document: content.document)
        if article.artwork == nil {
            article.artwork = recentFavicon(for: url)
        }
        return (article, url)
    }

    /// The page's best icon: from the live document, else the host's conventional icons.
    private func favicon(for url: URL) async -> Data? {
        await FaviconFetcher.best(for: url, webView: web.webView)
    }

    /// An icon already on hand for this page or its site (History).
    private func recentFavicon(for url: URL) -> Data? {
        guard let host = url.host else { return nil }
        let urlString = ArticleIdentity.canonicalURLString(from: url)
        return recentVisits.first {
            $0.urlString == urlString || $0.host.caseInsensitiveCompare(host) == .orderedSame
        }?.faviconData
    }
}

/// What a 🎧 tap came to.
enum ListenNowOutcome {
    /// The page plays, replacing what was playing.
    case started(ReaderArticle)
    /// Extraction failed or found too little text: nothing changed, and the caller says so.
    case nothingToListenTo
    /// Stop Listening, another ▶ or another 🎧 came first: nothing starts and nothing is said.
    case superseded
}
