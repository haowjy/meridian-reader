import SwiftUI

/// Now Playing: what you hear, opened up from the bar (`NowPlayingSheet`). A player on deep jade
/// (light and dark alike), the Reader's serif text in lyrics style under a title card. Presented
/// over everything by the shell; it holds no article of its own: it shows `speech.nowPlaying` and
/// the content its resolver finds.
///
/// - The title card (artwork, title, the site and time left) scrolls with the text.
/// - The text follows the audio: it opens with the spoken sentence near the middle and keeps it
///   there (each new paragraph, a long paragraph's sentence leaving the screen); the spoken
///   paragraph is in full ink and the others dimmed, its sentence underlined. A drag stops
///   following; Jump to Audio resumes it, back to the sentence. Scrubbing scrolls to the
///   paragraph under the thumb.
/// - The close pill names where the page plays from: a page in a folder plays from that folder (a
///   book, a series, Favorites, a folder you made), a saved page in no folder from the Library,
///   a page you haven't saved from its site. ⋯ → *Go to <name>* opens the Library at the folder
///   or the Library; for a site, ⋯ → Website opens the page in the browser.
/// - The top bar, 🔖 and ⋯ are the Reader's (decision D24): ☝︎ then a tap on a paragraph plays
///   from there; 🔖 saves / unsaves (tap) or files the page (long-press, *Save to Folder…*); ⋯ is
///   the Reader's menu.
/// - At the end it stays: the text stays, all in full ink, the title card says "✓ Finished"
///   (the one place it shows, where the Reader shows the page's length), ▶ plays it again.
/// - The pill or a pull down shrinks it back into the bar.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(DownloadCenter.self) private var downloads

    /// The reading content of the playing page, resolved by key.
    @State private var article: ReaderArticle?
    /// The page whose content has been looked up (found or not).
    @State private var loadedKey: UUID?
    /// The page's key when it is saved in the Library (🔖 filled).
    @State private var savedKey: UUID?
    @State private var following = true
    @State private var jumpMode = false
    @State private var scrubMap: ReaderScrubMap?
    @State private var scrubPreview: Int?
    @State private var scrollRequest: ReaderScrollRequest?

    var body: some View {
        if let now = speech.nowPlaying {
            NowPlayingSheet(
                playingFrom: playingFromName(now),
                showsJumpToAudio: !following && !now.isFinished,
                onCollapse: { [shell, presentation = shell.nowPlayingPresentation] in
                    if let presentation { shell.nowPlayingDidClose(presentation) }
                },
                onJumpToAudio: { following = true }
            ) {
                JumpModeButton(isOn: jumpMode) { jumpMode.toggle() }
                    .disabled(speech.document.isEmpty)
            } text: {
                text(now)
                    .overlay(alignment: .top) {
                        if jumpMode { JumpHint { jumpMode = false } }
                    }
                    .animation(Motion.snappy, value: jumpMode)
            } controls: {
                NowPlayingControls(
                    speech: speech, scrubMap: scrubMap, detectedLanguage: speech.sessionDetectedLanguage,
                    save: AnyView(SaveToggleButton(isSaved: savedKey != nil, identifier: "readerBookmark",
                                                   onToggle: toggleSaved, onSaveToFolder: saveToFolder)
                        .disabled(article == nil)),
                    more: AnyView(MoreMenuButton(id: "readerMore") { .reader(menu(now), perform: { perform($0, now) }) }
                        .foregroundStyle(Palette.playerInk)),
                    onScrubPreview: { p in
                        scrubPreview = p
                        if let p { scrollRequest = ReaderScrollRequest(index: p, token: (scrollRequest?.token ?? 0) + 1) }
                    }
                )
            } floating: {
                // The line at the band's top edge, as in the Reader; the toast floats above it.
                ZStack(alignment: .top) {
                    DownloadProgressEdge()
                    ShellToastLayer()
                }
            }
            .environment(\.sheetRisesOnAppear, shell.nowPlayingOpensAt == nil)
            .task(id: now.pageKey) { await load(now.pageKey) }
            .task(id: ScrubMapKey(key: now.pageKey, count: speech.document.count)) { await buildScrubMap() }
        } else {
            // Nothing is bound (crash resume found nothing to play): nothing to show.
            Color.clear.onAppear(perform: shell.hideNowPlaying)
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func text(_ now: NowPlaying) -> some View {
        if let html = readingHTML(now) {
            SpokenText(speech: speech, html: html,
                       card: TitleCardContent(title: article?.title ?? now.title, source: now.source,
                                              artwork: now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))),
                       finished: now.isFinished, scrubMap: scrubMap, scrubPreview: scrubPreview,
                       jumpMode: jumpMode, scrollRequest: scrollRequest, follows: following,
                       opensAt: shell.nowPlayingOpensAt,
                       onUserScroll: { following = false }, onTap: jump(to:))
        } else {
            Palette.playerBackground
        }
    }

    /// The page's reading HTML; for a plain-text article, or content that can't be found, the
    /// session's paragraphs as HTML, so every page reads, follows and underlines the same way.
    private func readingHTML(_ now: NowPlaying) -> String? {
        if let html = article?.displayHTML, html.contains(where: { !$0.isWhitespace }) { return html }
        guard loadedKey == now.pageKey, !speech.document.isEmpty else { return nil }
        return speech.document.paragraphsHTML
    }

    // MARK: - ⋯

    /// The Reader's menu for the page you hear, with *Go to* where it plays from.
    private func menu(_ now: NowPlaying) -> ReaderMenu {
        let page = savedPage
        return ReaderMenu(
            goTo: goToPlace(now),
            isSaved: savedKey != nil,
            canSave: article != nil,
            isFavorite: articleURL.flatMap { library.favorite(for: $0) } != nil,
            canFavorite: articleURL.map(LibraryStore.canFavorite) ?? false,
            canShare: shareURL != nil,
            canOpenWebsite: websiteURL != nil,
            showsDebug: speech.developerOptionsEnabled,
            canDownload: page.map { !downloads.isQueued(.page($0.listenKey)) } == true
        )
    }

    private var articleURL: URL? { article?.origin.url }

    private var websiteURL: URL? {
        guard let url = articleURL, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }

    private var shareURL: URL? {
        guard let url = articleURL, url.isWeb else { return nil }
        return url
    }

    /// The playing page's saved Library page, if it is saved.
    private var savedPage: Page? {
        guard let savedKey, let page = library.page(key: savedKey), page.isSavedToLibrary else { return nil }
        return page
    }

    private func perform(_ action: ReaderMenu.Action, _ now: NowPlaying) {
        switch action {
        case .goTo: goTo(now)
        case .voiceSettings: shell.present(.voiceSettings)
        case .toggleSave: toggleSaved()
        case .moveTo: saveToFolder()
        case .toggleFavorite: toggleFavorite()
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .download: if let savedPage { DownloadActions(downloads: downloads, shell: shell).download(savedPage) }
        case .downloads: shell.present(.downloads)
        case .listenDebug: speech.showListenDebug = true
        case .favorites: shell.showFavorites()
        case .history: shell.present(.history)
        case .openWebsite: openWebsite()
        }
    }

    // MARK: - Actions

    private func playingFromName(_ now: NowPlaying) -> String {
        if case .folder = now.playingFrom { return now.playingFrom.name }
        return savedKey != nil ? String(localized: "Library") : now.playingFrom.name
    }

    /// ⋯ → *Go to*: the folder the page plays from, or the Library for a saved page in none; nil
    /// for a page that plays from its site (⋯ → Website opens it).
    private func goToPlace(_ now: NowPlaying) -> ReaderMenu.Place? {
        if case .folder = now.playingFrom { return ReaderMenu.Place(name: now.playingFrom.name, symbol: Icons.folder) }
        return savedKey != nil ? ReaderMenu.Place(name: String(localized: "Library"), symbol: Icons.library) : nil
    }

    /// ⋯ → *Go to*: the Library at the folder, or the Library's home. Playback keeps going.
    private func goTo(_ now: NowPlaying) {
        if case .folder(let id, _) = now.playingFrom, let folder = library.folder(id: id) {
            shell.showLibrary(at: library.path(to: folder))
        } else {
            shell.showLibrary(at: [])
        }
    }

    /// ⋯ → Website: the page in the browser. Playback keeps going.
    private func openWebsite() {
        guard let websiteURL else { return shell.hideNowPlaying() }
        shell.openWebsite(websiteURL)
    }

    private func load(_ key: UUID) async {
        following = true
        jumpMode = false
        // 🔖 is right from the first frame; the address match below covers older saves.
        savedKey = savedPageKey(library.page(key: key))
        let loaded = await speech.nowPlayingContent()
        guard speech.activeSessionID == key else { return }
        article = loaded
        loadedKey = key
        if let loaded {
            savedKey = savedPageKey(library.page(key: loaded.id, canonicalURL: loaded.origin.canonicalURL)) ?? savedKey
        }
    }

    private func savedPageKey(_ page: Page?) -> UUID? {
        guard let page, page.isSavedToLibrary else { return nil }
        return page.listenKey
    }

    /// 🔖 / ⋯ → Save: saving never touches playback. A save or unsave that can't be stored
    /// leaves 🔖 as it was, and a toast says so.
    private func toggleSaved() {
        guard let article else { return }
        let saver = ArticleSaveCoordinator(library: library, speech: speech)
        if let savedKey {
            guard shell.attempt(String(localized: "Couldn’t remove from Library"), {
                try saver.unsave(key: savedKey, canonicalURL: article.origin.canonicalURL)
            }) != nil else { return }
            self.savedKey = nil
        } else if let key = shell.attempt(String(localized: "Couldn’t save"), { try saver.save(article) }) {
            savedKey = key
        }
    }

    /// 🔖's long-press (*Save to Folder…*) and ⋯ → Move to…: the Move tree, as in the Reader; the
    /// page is saved into the folder picked (a saved page moves there). A save or move that can't
    /// be stored keeps the tree up, with a toast saying so.
    private func saveToFolder() {
        guard let article else { return }
        let current: MoveRequest.Place? = savedPage.map { page in page.folder.map { .folder($0.id) } ?? .topLevel }
        FavoriteFlow(library: library, shell: shell).saveToFolder(
            title: current != nil ? String(localized: "Move to…") : String(localized: "Save to…"), current: current
        ) { [library, speech, shell, article] folder in
            if let saved = library.page(key: article.id, canonicalURL: article.origin.canonicalURL), saved.isSavedToLibrary {
                return shell.attempt(String(localized: "Couldn’t move")) { try library.move([.page(saved)], to: folder) } != nil
            }
            guard let key = shell.attempt(String(localized: "Couldn’t save"), {
                try ArticleSaveCoordinator(library: library, speech: speech).save(article, placement: .folder(folder))
            }) else { return false }
            savedKey = key
            return true
        }
    }

    /// ☆: the page in or out of Favorites (`FavoriteFlow`).
    private func toggleFavorite() {
        guard let article, let url = articleURL, LibraryStore.canFavorite(url) else { return }
        FavoriteFlow(library: library, shell: shell).toggle(url: url, title: article.title, artwork: article.artwork) {
            await FaviconFetcher.best(for: url, webView: nil)
        }
    }

    /// ☝︎ then a tap: play from that paragraph.
    private func jump(to index: Int) {
        guard jumpMode else { return }
        jumpMode = false
        following = true
        speech.play(fromParagraph: index)
    }

    private func buildScrubMap() async {
        let paragraphs = speech.document.paragraphs
        guard !paragraphs.isEmpty else { return }
        let map = await Task.detached(priority: .userInitiated) { ReaderScrubMap(paragraphs: paragraphs) }.value
        if !Task.isCancelled { scrubMap = map }
    }

    private struct ScrubMapKey: Hashable {
        let key: UUID
        let count: Int
    }
}

/// What the title card shows that doesn't move with the playhead.
private struct TitleCardContent {
    let title: String
    /// "example.com".
    let source: String
    let artwork: Image?
}

extension SpeechController {
    /// The paragraph Now Playing's text shows as spoken (full ink, the others dimmed): the one a
    /// scrub is over while it is dragged, else the playhead; none once the page has finished, so
    /// all of it reads in full ink.
    func spokenParagraph(scrubPreview: Int?) -> Int? {
        guard let now = nowPlaying, !now.isFinished else { return nil }
        return scrubPreview ?? currentParagraphIndex
    }
}

/// The text under its title card, the spoken paragraph in full ink and its sentence underlined.
/// Its own view because the sentence (and the card's time left) follows the live offset, which
/// moves several times a second: only this leaf (and the web view's bridge, which sends only
/// changes) redraws for it.
private struct SpokenText: View {
    let speech: SpeechController
    let html: String
    let card: TitleCardContent
    let finished: Bool
    let scrubMap: ReaderScrubMap?
    let scrubPreview: Int?
    let jumpMode: Bool
    let scrollRequest: ReaderScrollRequest?
    let follows: Bool
    let opensAt: ReadingHandOver?
    let onUserScroll: () -> Void
    let onTap: (Int) -> Void

    var body: some View {
        let paragraph = speech.currentParagraphIndex
        HTMLReadingView(
            html: html,
            look: .player,
            topView: titleCard,
            activeParagraphIndex: speech.spokenParagraph(scrubPreview: scrubPreview),
            sentence: finished || scrubPreview != nil ? nil : sentence(paragraph),
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: follows && !finished,
            opensAt: opensAt,
            onUserScroll: onUserScroll,
            onTapParagraph: onTap
        )
    }

    /// The title card: the site and time left (or "✓ Finished"). Replaced in the page only when its
    /// text changes, so once a minute at most while playing.
    private var titleCard: ReadingTopView {
        let doc = speech.document
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: speech.spokenUTF16Offset,
                                             rate: speech.rateMultiplier)
        let detail = finished ? [ListeningTime.finishedLabel]
            : [card.source, doc.isEmpty ? "" : ListeningTime.leftLabel(minutes: left)].filter { !$0.isEmpty }
        let letter = card.source.isEmpty ? card.title : card.source
        return ReadingTopView(
            id: [card.title, detail.joined(separator: "\n"), letter, card.artwork == nil ? "" : "artwork"],
            view: AnyView(TitleCard(title: card.title, detail: detail, artwork: card.artwork, artworkLetter: letter))
        )
    }

    private func sentence(_ paragraph: Int) -> ReaderSentence? {
        let doc = speech.document
        guard let scrubMap, doc.paragraphs.indices.contains(paragraph) else { return nil }
        let within = speech.spokenUTF16Offset - doc.startUTF16Offset(forParagraph: paragraph)
        guard let range = scrubMap.sentenceRange(paragraph: paragraph, offset: within) else { return nil }
        return ReaderSentence(paragraph: paragraph, start: range.lowerBound, end: range.upperBound)
    }
}

/// "Tap a paragraph to play from there", floating over the top of the text while ☝︎ is on. On the
/// player it sits on a `playerCard` capsule instead of the material.
struct JumpHint: View {
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.onPlayerPalette) private var onPlayer

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: Icons.jumpOn)
            Text("Tap a paragraph to play from there")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("listenJumpHint")
            Spacer(minLength: Spacing.xxs)
            Button("Cancel", action: onCancel)
                .typeStyle(.caption, weight: .semibold)
                .accessibilityIdentifier("listenJumpCancel")
        }
        .typeStyle(.caption)
        .foregroundStyle(onPlayer ? Palette.playerAccent : Palette.accent)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background { background }
        .padding(.horizontal, Spacing.s)
        .padding(.top, Spacing.xs)
        .transition(.slideAndFade(from: .top, reduceMotion: reduceMotion))
    }

    @ViewBuilder
    private var background: some View {
        if onPlayer {
            Capsule().fill(Palette.playerCard)
        } else {
            Capsule().fill(.thinMaterial)
        }
    }
}
