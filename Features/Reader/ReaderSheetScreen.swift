import SwiftUI
import SwiftData

/// The Reader sheet (`ReaderSheet`): one page for reading, over the surface that opened it, with
/// its own Listen. The back pill names what is underneath ("‹ Browser", "‹ Library"); it, the
/// grabber and a pull down close it to exactly where you were. Playback never stops for it.
///
/// - The Reader never shows what you hear (the shell opens Now Playing for that page), so the
///   Now Playing bar above its toolbar is always another page.
/// - Listen reads "▶ Listen  9 min", "▶ Resume  6 min left" (the time lighter, after the title)
///   or "▶ Listen Again", starts at
///   the page's saved spot, and turns the Reader into Now Playing where it was (decision D2).
///   ☝︎ in the header, then a tap on a paragraph, listens from that paragraph.
/// - A page part-way through opens with its saved spot's sentence in the middle, underlined;
///   after that the text never scrolls by itself.
/// - 🔖 saves / unsaves (tap) or files the page (long-press, *Save to Folder…*: the Move tree);
///   ⋯ is the reader menu (Save / Remove from Library, Move to…, Add to Favorites, Share, Voice
///   Settings, Debug; Favorites / History / Website).
///
/// Save / Unsave only flips 🔖: the article key is already the saved id (identity v2), so the
/// view and any playing audio are untouched.
struct ReaderSheetScreen: View {
    let state: ReaderSheetState
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(DownloadCenter.self) private var downloads
    /// The article's library page, if it has one (saved, played, or a favorite).
    @Query private var pages: [Page]
    @State private var jumpMode = false
    @State private var scroll = ReadingScrollHandle()

    init(state: ReaderSheetState, speech: SpeechController) {
        self.state = state
        _speech = Bindable(speech)
        let id = state.article.id
        // A page with no web address is found by its key alone; no page has an empty address.
        let canonical = state.article.origin.canonicalURL ?? ""
        _pages = Query(filter: #Predicate<Page> { $0.key == id || $0.canonicalURL == canonical })
    }

    private var article: ReaderArticle { state.article }

    private var page: Page? {
        pages.first { $0.key == article.id } ?? pages.first
    }

    private var isSaved: Bool { page?.isSavedToLibrary == true }

    private var sessionReady: Bool { !article.document.isEmpty }

    private var resumeParagraph: Int {
        page?.positionParagraph ?? article.resumeParagraph
    }

    private var isFinished: Bool {
        page?.finishedAt != nil
    }

    var body: some View {
        ReaderSheet(
            backTitle: state.origin.backTitle,
            listenTitle: listen.title,
            listenDetail: listen.detail,
            listenState: speech.playState(of: .page(article.id)),
            isSaved: isSaved,
            onClose: { [shell, presentation = state.presentation] in shell.readerDidClose(presentation) },
            onListen: { listen(from: nil) },
            onToggleSave: toggleSaved,
            onSaveToFolder: saveToFolder
        ) {
            jumpButton
        } text: {
            text
                .overlay(alignment: .top) {
                    if jumpMode { JumpHint { jumpMode = false } }
                }
                .animation(Motion.snappy, value: jumpMode)
        } bar: {
            NowPlayingBarView(speech: speech)
        } more: {
            MoreMenuButton(id: "readerMore") { .reader(readerMenu, perform: perform) }
                .foregroundStyle(Palette.ink)
        } floating: {
            // The line at the band's top edge; the toast floats above it.
            ZStack(alignment: .top) {
                DownloadProgressEdge()
                ShellToastLayer()
            }
        }
        .task(id: WarmKey(id: article.id, count: article.document.count)) {
            prepareListen()
        }
    }

    // MARK: - Text

    @ViewBuilder
    private var text: some View {
        // A plain-text article reads as its paragraphs, on the same page.
        let html = article.displayHTML.contains(where: { !$0.isWhitespace })
            ? article.displayHTML : article.document.paragraphsHTML
        HTMLReadingView(html: html, heading: ReaderHeading(title: article.title, detail: detail),
                        activeParagraphIndex: nil, sentence: savedSentence, jumpMode: jumpMode,
                        opensAtSentence: true, scrollHandle: scroll) { index in
            if jumpMode { listen(from: index) }
        }
    }

    /// The sentence at the page's saved listening spot, while it is part-way through: the text
    /// opens with it in the middle, underlined, where Resume starts.
    private var savedSentence: ReaderSentence? {
        let offset = page?.positionUTF16 ?? 0
        guard !isFinished, resumeParagraph > 0 || offset > 0 else { return nil }
        return ReaderSentence(in: article.document, paragraph: resumeParagraph, utf16Offset: offset)
    }

    private var totalLength: Int {
        sessionReady ? article.document.utf16Length : article.plainText.utf16.count
    }

    /// The source and the length, as separate parts: ["example.org", "9 min"].
    private var detail: [String] {
        let minutes = ListeningTime.minutes(utf16Length: totalLength)
        return [article.sourceLabel, minutes > 0 ? "\(minutes) min" : ""].filter { !$0.isEmpty }
    }

    /// Listen's title and the lighter time after it: "Listen" "9 min", "Resume" "6 min left",
    /// "Listen Again".
    private var listen: (title: String, detail: String?) {
        if isFinished { return (String(localized: "Listen Again"), nil) }
        let doc = article.document
        if resumeParagraph > 0, doc.paragraphs.indices.contains(resumeParagraph) {
            let at = doc.startUTF16Offset(forParagraph: resumeParagraph)
            return (String(localized: "Resume"), "\(ListeningTime.minutesLeft(in: doc, fromUTF16Offset: at)) min left")
        }
        return (String(localized: "Listen"), "\(ListeningTime.minutes(utf16Length: totalLength)) min")
    }

    private var jumpButton: some View {
        Button { jumpMode.toggle() } label: {
            Image(systemName: jumpMode ? "hand.tap.fill" : "hand.tap")
                .foregroundStyle(jumpMode ? Palette.accent : Palette.ink)
                .fieldControlFrame()
                .background(Circle().fill(jumpMode ? Palette.playingTint : Palette.chrome))
        }
        .buttonStyle(.plain)
        .disabled(!sessionReady)
        .accessibilityIdentifier("listenJump")
        .accessibilityLabel(jumpMode ? "Cancel listen from a paragraph" : "Listen from a paragraph")
    }

    // MARK: - ⋯ menu

    private var readerMenu: ReaderMenu {
        ReaderMenu(
            isSaved: isSaved,
            canSave: sessionReady,
            isFavorite: library.favorite(for: articleURL) != nil,
            canFavorite: articleURL.map(LibraryStore.canFavorite) ?? false,
            canShare: shareURL != nil,
            canOpenWebsite: websiteURL != nil,
            showsDebug: speech.developerOptionsEnabled,
            canDownload: isSaved && page.map { !downloads.isQueued(.page($0.listenKey)) } == true
        )
    }

    private var articleURL: URL? { article.origin.url }

    /// The article's own page, for ⋯ → Website (any loadable page URL, not just http(s)).
    private var websiteURL: URL? {
        guard let url = articleURL, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }

    private var shareURL: URL? {
        guard let url = articleURL, url.isWeb else { return nil }
        return url
    }

    private func perform(_ action: ReaderMenu.Action) {
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .toggleSave: toggleSaved()
        case .moveTo: saveToFolder()
        case .toggleFavorite: toggleFavorite()
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .download: if let page { DownloadActions(downloads: downloads, shell: shell).download(page) }
        case .downloads: shell.present(.downloads)
        case .listenDebug: speech.showListenDebug = true
        case .favorites: shell.present(.favorites())
        case .history: shell.present(.history)
        // Reader off = the article's own web page in the browser, wherever the Reader was opened
        // from. Playback keeps going.
        case .openWebsite: if let websiteURL { shell.openWebsite(websiteURL) } else { shell.closeReader() }
        }
    }

    /// ☆: the article's page in or out of Favorites (`FavoriteFlow`).
    private func toggleFavorite() {
        guard let url = articleURL, LibraryStore.canFavorite(url) else { return }
        FavoriteFlow(library: library, shell: shell).toggle(url: url, title: article.title, artwork: article.artwork) {
            await FaviconFetcher.best(for: url, webView: nil)
        }
    }

    /// 🔖's long-press (*Save to Folder…*) and ⋯ → Move to…: the Move tree; the page is saved
    /// into the folder picked (a saved page moves there). A save or move that can't be stored
    /// keeps the tree up, with a toast saying so.
    private func saveToFolder() {
        guard sessionReady else { return }
        let current: MoveRequest.Place? = isSaved ? (page?.folder.map { .folder($0.id) } ?? .topLevel) : nil
        FavoriteFlow(library: library, shell: shell).saveToFolder(
            title: isSaved ? String(localized: "Move to…") : String(localized: "Save to…"), current: current
        ) { [library, speech, shell, article] folder in
            if let saved = library.page(key: article.id, canonicalURL: article.origin.canonicalURL), saved.isSavedToLibrary {
                return shell.attempt(String(localized: "Couldn’t move")) { try library.move([.page(saved)], to: folder) } != nil
            }
            guard let savedID = shell.attempt(String(localized: "Couldn’t save"), {
                try ArticleSaveCoordinator(library: library, speech: speech).save(article, placement: .folder(folder))
            }) else { return false }
            if savedID != article.id { shell.updateReader(id: article.id) { $0.id = savedID } }
            return true
        }
    }

    // MARK: - Actions

    /// Listen (`paragraph` nil: from the page's saved spot; a finished page from the start), or
    /// ☝︎ then a tap on a paragraph. The page becomes what you hear, and the Reader turns into Now
    /// Playing at the same scroll position.
    private func listen(from paragraph: Int?) {
        guard sessionReady else { return }
        jumpMode = false
        let handOver = scroll.handOver
        if let paragraph {
            speech.listen(to: article, fromParagraph: paragraph)
        } else if isFinished {
            speech.listen(to: article, fromParagraph: 0)
        } else {
            speech.listen(to: article, fromParagraph: resumeParagraph, utf16Offset: page?.positionUTF16)
        }
        shell.turnReaderIntoNowPlaying(handOver: handOver)
    }

    /// 🔖 / ⋯ → Save. Neither direction touches the screen or playback (see the type comment).
    private func toggleSaved() {
        let saver = ArticleSaveCoordinator(library: library, speech: speech)
        if isSaved {
            shell.attempt(String(localized: "Couldn’t remove from Library")) {
                try saver.unsave(key: page?.listenKey ?? article.id, canonicalURL: article.origin.canonicalURL)
            }
            return
        }
        guard let savedID = shell.attempt(String(localized: "Couldn’t save"), { try saver.save(article) }) else { return }
        if savedID != article.id { shell.updateReader(id: article.id) { $0.id = savedID } }
    }

    /// Identity alignment + the first audio for this article, so Listen starts quickly. The Reader
    /// never shows what is playing, so this never touches live playback.
    private func prepareListen() {
        guard sessionReady else { return }
        let paragraphs = article.document.paragraphs
        ListenTimingLog.log("reader_open", [
            "key": ListenTimingLog.shortKey(article.id),
            "paragraphs": paragraphs.count,
            "chars": paragraphs.reduce(0) { $0 + $1.count },
            "resume_p": resumeParagraph,
            "local_ready": speech.localTTS.usesLocalEngine,
            "saved": isSaved,
        ])
        speech.localTTS.prepareListenIdentity(
            key: article.id,
            paragraphs: paragraphs,
            trustedParagraphs: article.trustedParagraphs,
            legacyKeys: article.legacyCacheKeys,
            isLivePlayback: false
        )
        speech.localTTS.warmListenAudio(
            cacheKey: article.id,
            paragraphs: paragraphs,
            voiceID: speech.cacheVoiceID,
            resumeParagraph: resumeParagraph,
            isEphemeral: !isSaved
        )
    }

    private struct WarmKey: Hashable {
        let id: UUID
        let count: Int
    }
}
