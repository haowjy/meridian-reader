import SwiftUI

/// Now Playing: what you hear, opened up from the bar (`NowPlayingSheet`). The Reader's page in
/// the same reading theme and type, under a title card: the spoken paragraph highlighted in full
/// ink like the rest, on the highlight. Presented over everything by the shell (in place under the
/// bottom chrome on compact width, a sheet on regular width); it holds no article of its
/// own: it shows `speech.nowPlaying` and the playing page's content, looked up in the library by
/// its key. On compact width the chrome draws its player card (`ChromeCard`), the same card as the
/// Reader's.
///
/// - The title card (artwork, title, the site and time left) scrolls with the text.
/// - The text follows the audio: it opens with the spoken sentence near the middle and keeps it
///   there (each new paragraph, a long paragraph's sentence leaving the screen); the spoken
///   paragraph is highlighted (every paragraph in full ink), its sentence underlined. A drag stops
///   following; Jump to Audio resumes it, back to the sentence. Scrubbing scrolls to the
///   paragraph under the thumb.
/// - On regular width the close pill names where the page plays from: a page in a folder plays from that folder (a
///   book, a series, Favorites, a folder you made), a saved page in no folder from the Library,
///   a page you haven't saved from its site. ⋯ → *Go to <name>* opens the Library at the folder
///   or the Library; for a site, ⋯ → Website opens the page in the browser.
/// - The top bar, 🔖 and ⋯ are the Reader's (decision D24): Aa changes how the page reads; ☝︎
///   then a tap on a paragraph plays from there; 🔖 saves / removes (tap) or files the page
///   (long-press, *Save to Folder…*); ⋯ is the Reader's menu. Both act through `ArticleActions`, as
///   in the Reader. Voice (`VoiceChromeButton`) sits to the right of the title in the bottom band
///   and opens the same Voice picker as ⋯ › Voice.
/// - At the end it stays: the text stays, all in full ink, the title card says "● Finished" (the ring, full)
///   (the one place it shows, where the Reader shows the page's length), ▶ plays it again.
/// - A tap in the middle of the text reads full screen, as in the Reader (`ReadingPage`,
///   `ReadingChrome`): the text still follows the audio, a page turn by a tap stops following as a drag does, and a link
///   in the text opens in the browser.
/// - On compact width Library or Browser in the pill leaves it; on regular width the pill or a pull
///   down shrinks it back into the bar.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(DeveloperSettings.self) private var developer
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.horizontalSizeClass) private var sizeClass

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
        let palette = appearance.palette(accent: AppAppearance.shared.accent)
        let artwork = now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        let compactCard = sizeClass == .regular ? nil : card(now, actions, artwork: artwork)
        return NowPlayingSheet(
            showing: shell.readingShowing(
                regular: sizeClass == .regular, close: .collapse(playingFromName(now, saved: actions.isSaved)),
                onClose: { [shell, presentation = shell.nowPlayingPresentation] in
                    if let presentation { shell.nowPlayingDidClose(presentation) }
                }),
            playState: speech.playState(of: .article(now.articleKey)),
            showsJumpToAudio: !following && !now.isFinished,
            onPlayPause: speech.pressNowPlaying,
            onJumpToAudio: { following = true },
            palette: palette
        ) {
            TextAppearanceControl()
        } accessory: {
            JumpModeButton(isOn: jumpMode) { withAnimation(Motion.snappy) { jumpMode.toggle() } }
                .disabled(speech.document.isEmpty)
        } banner: {
            if jumpMode { JumpHint { withAnimation(Motion.snappy) { jumpMode = false } } }
        } text: {
            text(now, readerArticle: actions.readerArticle)
        } band: {
            PlayheadReader(speech: speech) { spot in
                bandContent(now: now, actions: actions, palette: palette, artwork: artwork, spot: spot)
            }
        } floating: {
            // The toast floats above the hairline.
            ZStack(alignment: .top) {
                PrepareProgressEdge()
                ShellToastLayer()
            }
        }
        .chromeCard(compactCard)
    }

    /// Compact width: the card the chrome draws above row 2, and ⋯'s row for ☝︎.
    private func card(_ now: NowPlaying, _ actions: ArticleActions, artwork: Image?) -> ChromeCard {
        let view = PlayheadReader(speech: speech) { spot in
            let doc = speech.document
            let rate = speech.rateMultiplier
            let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: spot.utf16Offset, rate: rate)
            let source = ArticleRowTitle.lineTwoSource(title: now.title, source: now.source)
            let note = NowPlayingControls.note(of: speech, detectedLanguage: speech.sessionDetectedLanguage)
            ReaderPlayerCard(
                title: now.lineOne,
                detail: note ?? (now.isFinished ? String(localized: "Finished")
                    : [source, left > 0 ? ListeningTime.leftLabel(minutes: left) : nil].compactMap { $0 }.joined(separator: " · ")),
                artwork: artwork, artworkLetter: now.artworkLetter, playState: speech.playState(of: .article(now.articleKey)),
                canSkip: speech.canSkipToPreviousParagraph || speech.canSkipToNextParagraph,
                onSkipBack: speech.skipToPreviousParagraph, onSkipForward: speech.skipToNextParagraph,
                onPlayPause: speech.pressNowPlaying,
                onPlayLongPress: developer.isEnabled ? { shell.present(.listenDebug) } : nil,
                origin: actions.cardOrigin(title: now.lineOne)
            ) {
                VoiceChromeButton(identifier: "nowPlayingVoice") { shell.present(.voice(.article(now.articleKey))) }
            } save: {
                SaveToggleButton(isSaved: actions.isSaved, identifier: "nowPlayingBookmark",
                                 onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder, round: true)
                    .disabled(actions.readerArticle == nil)
            } scrub: {
                playerScrub(spot: spot) { EmptyView() }
            } appearance: {
                TextAppearanceControl(arrowEdge: .bottom)
            } speed: {
                SpeedButton(speech: speech, round: true)
            }
        }
        let jump = MenuRow(id: "listenJump", title: Verbs.playFromParagraph, icon: Icons.jump,
                           availability: MenuAvailability(when: !speech.document.isEmpty)) {
            withAnimation(Motion.snappy) { jumpMode.toggle() }
        }
        return ChromeCard(content: AnyView(view), menuRows: [jump])
    }

    /// The integrated bottom band: title + Voice (trailing), scrub, notes, transport — all flat on
    /// the page background.
    @ViewBuilder
    private func bandContent(now: NowPlaying, actions: ArticleActions, palette: ReadingPalette,
                             artwork: Image?, spot: PlayheadSpot) -> some View {
        let doc = speech.document
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: spot.utf16Offset, rate: speech.rateMultiplier)
        let timeDetail = now.isFinished ? String(localized: "Finished")
            : (left > 0 ? ListeningTime.leftLabel(minutes: left) : nil)

        VStack(spacing: Spacing.xs) {
            // Title row: title + time detail
            HStack(alignment: .center, spacing: Spacing.s) {
                if let artwork {
                    ArtworkTile(image: artwork, letter: now.artworkLetter, size: PlayerCard.artworkSize)
                } else {
                    ArtworkTile(letter: now.artworkLetter.isEmpty ? now.lineOne : now.artworkLetter,
                                size: PlayerCard.artworkSize)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(now.lineOne)
                        .typeStyle(.row, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    if let timeDetail {
                        Text(timeDetail)
                            .typeStyle(.caption)
                            .foregroundStyle(palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Voice, aligned right of the title (⋯ › Voice / Settings › Voice's same picker).
                VoiceChromeButton(identifier: "nowPlayingVoice") {
                    shell.present(.voice(.article(now.articleKey)))
                }
            }

            // Scrub row
            playerScrub(spot: spot) { SpeedButton(speech: speech) }

            // Notes (buffering, language, etc.)
            NowPlayingControls(speech: speech, detectedLanguage: speech.sessionDetectedLanguage)

            // Transport: [🔖] [⏮] (⏸) [⏭] [⋯]
            ListenTransportView(
                leading: AnyView(SaveToggleButton(isSaved: actions.isSaved, identifier: "nowPlayingBookmark",
                                                   onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder)
                    .disabled(actions.readerArticle == nil)),
                // Compact width: the chrome's ⋯ (`ReadingPageMoreButton`) is the page's menu.
                trailing: sizeClass == .regular ? AnyView(ReadingPageMoreButton(id: "nowPlayingMore")) : nil,
                speech: speech
            )
        }
    }

    /// The scrub row: a bare ReaderScrubRow with `trailing` after it, or a placeholder until the
    /// map is ready.
    @ViewBuilder
    private func playerScrub<Trailing: View>(spot: PlayheadSpot, @ViewBuilder trailing: () -> Trailing) -> some View {
        if let scrubMap {
            ReaderScrubRow(
                map: scrubMap,
                position: Self.scrubFraction(scrubMap, document: speech.document, spot: spot),
                buffered: bufferedSpans(scrubMap),
                onScrubPreview: { p in
                    scrubPreview = p
                    if p != nil { jumpMode = false }
                    if let p { scrollRequest = ReaderScrollRequest(index: p, token: (scrollRequest?.token ?? 0) + 1) }
                },
                onScrubCommit: seek(to:),
                trailing: trailing,
                isCapsule: false
            )
        } else {
            // Placeholder: keeps height stable until scrub map builds.
            HStack(spacing: 0) {
                Color.clear.frame(height: BottomChrome.fieldControlSize)
                    .frame(maxWidth: .infinity)
                trailing()
            }
        }
    }

    /// Scrubber fraction of `spot`. `ReaderScrubMap` keeps a spot inside its paragraph (< 1 of
    /// it), so the end of a paragraph never reads as the start of the next one.
    private static func scrubFraction(_ map: ReaderScrubMap, document doc: ParagraphDocument,
                                      spot: PlayheadSpot) -> Double {
        guard doc.paragraphs.indices.contains(spot.paragraph) else { return map.fraction(paragraph: spot.paragraph) }
        return map.fraction(paragraph: spot.paragraph,
                            offset: spot.utf16Offset - doc.startUTF16Offset(forParagraph: spot.paragraph))
    }

    /// Lighter "buffered" fill: stretches of rendered audio, as scrubber fractions.
    private func bufferedSpans(_ map: ReaderScrubMap) -> [ClosedRange<Double>] {
        guard let id = speech.activeSessionID,
              let ready = speech.bakeReadyParagraphIndices(articleID: id, paragraphCount: speech.document.count,
                                                           detectedLanguage: speech.sessionDetectedLanguage),
              !ready.isEmpty else { return [] }
        return map.spans(covering: ready)
    }

    /// Scrubber release: seeks the playhead to the sentence under the thumb.
    private func seek(to target: ReaderScrubMap.Target) {
        let doc = speech.document
        guard !doc.isEmpty else { return }
        speech.seek(toUTF16Offset: doc.startUTF16Offset(forParagraph: target.paragraph) + target.offset)
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

    /// The playing page changed: its content, and the text following the audio again.
    private func load(_ key: UUID) {
        following = true
        jumpMode = false
        content = NowPlayingContent(key: key, readerArticle: library.nowPlayingContent(for: key))
    }

    /// ☝︎ then a tap: play from that paragraph.
    private func jump(to index: Int) {
        // Only ☝︎'s deliberate tap seeks, never a tap while a scrub is up.
        guard jumpMode, scrubPreview == nil else { return }
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
            heading: ReaderHeading(title: card.title, detail: [], titleHidden: true),
            topView: nil,
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
