import SwiftUI

/// Now Playing: what you hear, opened up from the bar (`NowPlayingSheet`). The Reader's page in
/// the same reading theme and type, under a title card: the spoken paragraph highlighted in full
/// ink like the rest, on the highlight. Presented over everything by the shell; it holds no article of its
/// own: it shows `speech.nowPlaying` and the playing page's content, looked up in the library by
/// its key.
///
/// - The title card (artwork, title, the site and time left) scrolls with the text.
/// - The text follows the audio: it opens with the spoken sentence near the middle and keeps it
///   there (each new paragraph, a long paragraph's sentence leaving the screen); the spoken
///   paragraph is highlighted (every paragraph in full ink), its sentence underlined. A drag stops
///   following; Jump to Audio resumes it, back to the sentence. Scrubbing scrolls to the
///   paragraph under the thumb.
/// - The close pill names where the page plays from: a page in a folder plays from that folder (a
///   book, a series, Favorites, a folder you made), a saved page in no folder from the Library,
///   a page you haven't saved from its site. ⋯ → *Go to <name>* opens the Library at the folder
///   or the Library; for a site, ⋯ → Website opens the page in the browser.
/// - The top bar, 🔖 and ⋯ are the Reader's (decision D24): Aa changes how the page reads; ☝︎
///   then a tap on a paragraph plays from there; 🔖 saves / removes (tap) or files the page
///   (long-press, *Save to Folder…*); ⋯ is the Reader's menu. Both act through `ArticleActions`, as
///   in the Reader.
/// - At the end it stays: the text stays, all in full ink, the title card says "● Finished" (the ring, full)
///   (the one place it shows, where the Reader shows the page's length), ▶ plays it again.
/// - Scrolling down reads full screen, as in the Reader (`NowPlayingSheet`, `ReadingChrome`): the
///   text still follows the audio, a page turn by a tap stops following as a drag does, and a link
///   in the text opens in the browser.
/// - The pill or a pull down shrinks it back into the bar.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(\.readingAppearance) private var appearance

    /// The playing page's reading content, looked up by key when the page changes.
    @State private var content: NowPlayingContent?
    @State private var following = true
    @State private var jumpMode = false
    @State private var scrubMap: ReaderScrubMap?
    @State private var scrubPreview: Int?
    @State private var scrollRequest: ReaderScrollRequest?

    var body: some View {
        if let now = speech.nowPlaying {
            // Only the playing page's content: never the page before's, for a frame, on advance.
            let readerArticle = content?.key == now.articleKey ? content?.readerArticle : nil
            ArticleLookup(key: now.articleKey, canonicalURL: readerArticle?.origin.canonicalURL) { article in
                player(now, ArticleActions(article: article, readerArticle: readerArticle, library: library, shell: shell, speech: speech,
                                        preparedAudio: preparedAudio, follow: follow))
            }
            .environment(\.sheetRisesOnAppear, shell.nowPlayingOpensAt == nil)
            .onChange(of: now.articleKey, initial: true) { _, key in load(key) }
            .task(id: ScrubMapKey(key: now.articleKey, count: speech.document.count)) { await buildScrubMap() }
        } else {
            // Nothing is bound (the page you heard was removed from the Library or deleted, or
            // crash resume found nothing to play): nothing to show.
            Color.clear.onAppear(perform: shell.hideNowPlaying)
        }
    }

    private func player(_ now: NowPlaying, _ actions: ArticleActions) -> some View {
        NowPlayingSheet(
            playingFrom: playingFromName(now, saved: actions.isSaved),
            playState: speech.playState(of: .article(now.articleKey)),
            showsJumpToAudio: !following && !now.isFinished,
            onCollapse: { [shell, presentation = shell.nowPlayingPresentation] in
                if let presentation { shell.nowPlayingDidClose(presentation) }
            },
            onPlayPause: speech.pressNowPlaying,
            onJumpToAudio: { following = true },
            palette: appearance.palette(accent: AppAppearance.shared.accent)
        ) {
            TextAppearanceControl()
        } accessory: {
            JumpModeButton(isOn: jumpMode) { withAnimation(Motion.snappy) { jumpMode.toggle() } }
                .disabled(speech.document.isEmpty)
        } banner: {
            if jumpMode { JumpHint { withAnimation(Motion.snappy) { jumpMode = false } } }
        } text: {
            text(now, readerArticle: actions.readerArticle)
        } controls: {
            NowPlayingControls(
                speech: speech, scrubMap: scrubMap, detectedLanguage: speech.sessionDetectedLanguage,
                save: AnyView(SaveToggleButton(isSaved: actions.isSaved, identifier: "nowPlayingBookmark",
                                               onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder)
                    .disabled(actions.readerArticle == nil)),
                more: AnyView(MoreMenuButton(id: "nowPlayingMore") { actions.readingPageMenu(.nowPlaying(goTo(now, actions))) }),
                onScrubPreview: { p in
                    scrubPreview = p
                    if let p { scrollRequest = ReaderScrollRequest(index: p, token: (scrollRequest?.token ?? 0) + 1) }
                }
            )
        } floating: {
            // The line at the band's top edge, as in the Reader; the toast floats above it.
            ZStack(alignment: .top) {
                PrepareProgressEdge()
                ShellToastLayer()
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func text(_ now: NowPlaying, readerArticle: ReaderArticle?) -> some View {
        if let html = readingHTML(now, readerArticle: readerArticle) {
            SpokenText(speech: speech, html: html,
                       card: TitleCardContent(title: readerArticle?.title ?? now.title, source: now.source,
                                              address: now.canonicalURL, letter: now.artworkLetter,
                                              artwork: now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))),
                       finished: now.isFinished, isChapter: now.isChapter, scrubMap: scrubMap,
                       scrubPreview: scrubPreview,
                       jumpMode: jumpMode, scrollRequest: scrollRequest, follows: following,
                       opensAt: shell.nowPlayingOpensAt,
                       onUserScroll: { following = false }, onTap: jump(to:), onOpenLink: shell.navigate(to:),
                       onPlaySelection: playFromSelection)
        } else {
            appearance.palette(accent: AppAppearance.shared.accent).background
        }
    }

    /// The page's reading HTML; for a plain-text article, or content that can't be found, the
    /// session's paragraphs as HTML, so every page reads, follows and underlines the same way.
    /// Nothing until the page's content has been looked up.
    private func readingHTML(_ now: NowPlaying, readerArticle: ReaderArticle?) -> String? {
        if let html = readerArticle?.displayHTML, html.contains(where: { !$0.isWhitespace }) { return html }
        guard content?.key == now.articleKey, !speech.document.isEmpty else { return nil }
        return speech.document.paragraphsHTML
    }

    // MARK: - Actions

    private func playingFromName(_ now: NowPlaying, saved: Bool) -> String {
        if case .folder = now.playingFrom { return now.playingFrom.name }
        return saved ? Verbs.library : now.playingFrom.name
    }

    /// ⋯ → *Go to*: the folder the page plays from, or the Library's home for a saved page in
    /// none; dimmed *Go to Library* for a page that plays from its site (⋯ → Website opens it).
    /// Playback keeps going.
    private func goTo(_ now: NowPlaying, _ actions: ArticleActions) -> ArticleMenu.GoTo {
        if case .folder(let id, _) = now.playingFrom {
            return ArticleMenu.GoTo(name: now.playingFrom.name, symbol: Icons.folder, availability: .enabled) { [shell, library] in
                if let folder = library.folder(id: id) { shell.showLibrary(at: library.path(to: folder)) }
            }
        }
        return ArticleMenu.GoTo(name: Verbs.library, symbol: Icons.library,
                             availability: MenuAvailability(when: actions.isSaved)) { [shell] in shell.showLibrary(at: []) }
    }

    /// The playing page changed: its content, and the text following the audio again.
    private func load(_ key: UUID) {
        following = true
        jumpMode = false
        content = NowPlayingContent(key: key, readerArticle: library.nowPlayingContent(for: key))
    }

    /// ☝︎ then a tap: play from that paragraph.
    private func jump(to index: Int) {
        guard jumpMode else { return }
        jumpMode = false
        following = true
        speech.play(fromParagraph: index)
    }

    /// *Play from Here* on a selection (C109): from its sentence's start.
    private func playFromSelection(paragraph: Int, offset: Int) {
        guard let spot = ListenSpot.fromSelection(in: speech.document, paragraph: paragraph, offset: offset) else { return }
        jumpMode = false
        following = true
        speech.play(fromParagraph: spot.paragraph)
        if spot.utf16Offset > speech.document.startUTF16Offset(forParagraph: spot.paragraph) {
            speech.seek(toUTF16Offset: spot.utf16Offset)
        }
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

/// The reading content looked up for a playing page (nil: it can't be found).
private struct NowPlayingContent {
    let key: UUID
    let readerArticle: ReaderArticle?
}

/// What the title card shows that doesn't move with the playhead.
private struct TitleCardContent {
    /// nil: the page has none.
    let title: String?
    /// "example.com".
    let source: String
    /// The page's address, for line one of a page with neither title nor site.
    let address: String?
    /// On the artwork tile when there is no artwork.
    let letter: String
    let artwork: Image?
}

extension SpeechController {
    /// The paragraph Now Playing's text shows as spoken (on the highlight, all in full ink): the one a
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
    let isChapter: Bool
    let scrubMap: ReaderScrubMap?
    let scrubPreview: Int?
    let jumpMode: Bool
    let scrollRequest: ReaderScrollRequest?
    let follows: Bool
    let opensAt: ReadingHandOver?
    let onUserScroll: () -> Void
    let onTap: (Int) -> Void
    let onOpenLink: (URL) -> Void
    var onPlaySelection: ((Int, Int) -> Void)?

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let paragraph = speech.currentParagraphIndex
        HTMLReadingView(
            html: html,
            heading: ReaderHeading(title: card.title, detail: []),
            topView: titleCard,
            activeParagraphIndex: speech.spokenParagraph(scrubPreview: scrubPreview),
            sentence: finished || scrubPreview != nil ? nil : sentence(paragraph),
            spokenWord: finished || scrubPreview != nil ? nil : spokenWord(paragraph),
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: follows && !finished,
            opensAt: opensAt,
            onUserScroll: onUserScroll,
            onOpenLink: onOpenLink,
            pageTimeLeft: { [document = speech.document, rate = speech.rateMultiplier, isChapter] in
                ListeningTime.leftLabel(in: document, paragraph: $0, offset: $1, rate: rate, chapter: isChapter)
            },
            onPlaySelection: onPlaySelection,
            onTapParagraph: onTap
        )
    }

    /// The title card: the site and time left (or the full ring and Finished). Replaced in the page only when its
    /// text changes, so once a minute at most while playing.
    private var titleCard: ReadingTopView {
        let doc = speech.document
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: speech.spokenUTF16Offset,
                                             rate: speech.rateMultiplier)
        // As the bar: line one is `lineOne`, line two starts with `lineTwoSource`.
        let lineOne = ArticleRowTitle.lineOne(title: card.title, source: card.source, address: card.address)
        let detail: [DetailPart] = finished ? [.finished]
            : [ArticleRowTitle.lineTwoSource(title: card.title, source: card.source),
               doc.isEmpty ? nil : ListeningTime.leftLabel(minutes: left)]
                .compactMap { $0 }.map { DetailPart($0) }
        let palette = reading ?? .app
        return ReadingTopView(
            id: [lineOne, detail.map(\.text).joined(separator: "\n"), card.letter, card.artwork == nil ? "" : "artwork",
                 palette.theme.rawValue, AppAppearance.shared.accent.rawValue],
            view: AnyView(TitleCard(title: lineOne, detail: detail, artwork: card.artwork, artworkLetter: card.letter,
                                    palette: palette))
        )
    }

    /// The word being spoken: its paragraph and the UTF-16 offset in it.
    private func spokenWord(_ paragraph: Int) -> ReadingPages.Spot? {
        let doc = speech.document
        guard doc.paragraphs.indices.contains(paragraph) else { return nil }
        return ReadingPages.Spot(paragraph: paragraph,
                                 offset: speech.spokenUTF16Offset - doc.startUTF16Offset(forParagraph: paragraph))
    }

    private func sentence(_ paragraph: Int) -> ReaderSentence? {
        let doc = speech.document
        guard let scrubMap, doc.paragraphs.indices.contains(paragraph) else { return nil }
        let within = speech.spokenUTF16Offset - doc.startUTF16Offset(forParagraph: paragraph)
        guard let range = scrubMap.sentenceRange(paragraph: paragraph, offset: within) else { return nil }
        return ReaderSentence(paragraph: paragraph, start: range.lowerBound, end: range.upperBound)
    }
}

/// "Tap a paragraph to play from there", under the top bar while ☝︎ is on (the reading sheets'
/// `banner`), its capsule at the page margin like the text under it, on the reading page's card
/// colour. It is part of the header drawn over the text, so the text's top inset grows with it and
/// it never covers the first line.
struct JumpHint: View {
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingPalette) private var reading

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: Icons.jumpOn)
            Text("Tap a paragraph to play from there")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("listenJumpHint")
            Spacer(minLength: Spacing.xxs)
            Button(Verbs.cancel, action: onCancel)
                .typeStyle(.caption, weight: .semibold)
                .accessibilityIdentifier("listenJumpCancel")
        }
        .typeStyle(.caption)
        .foregroundStyle(reading?.accent ?? Palette.accent)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(reading?.card ?? Palette.chrome, in: Capsule())
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.vertical, Spacing.xs)
        .transition(.slideAndFade(from: .top, reduceMotion: reduceMotion))
    }
}
