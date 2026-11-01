import SwiftUI

/// Now Playing, Listen: what you hear, opened up (`NowPlayingSheet`). The Reader's page in the
/// same reading theme and type: the spoken paragraph highlighted in full ink like the rest, on the
/// highlight. Presented over everything by the shell: on compact width a cover that slides up over
/// the chrome too, the reading pages' top group at its top, the grabber between Aa and ⋯ (`ReadingTopGroup`), and the
/// player card at its foot (`ReaderPlayerCard`: Save, speed, Voice); on regular width a sheet. It holds no article of its own: it shows `speech.nowPlaying` and the
/// playing page's content, looked up in the library by its key.
///
/// - The text follows the audio: it opens with the spoken sentence near the middle and keeps it
///   there (each new paragraph, a long paragraph's sentence leaving the screen); the spoken
///   paragraph is highlighted (every paragraph in full ink), its sentence underlined. A drag stops
///   following; Jump to Audio, floating in the middle above the card while the text is away,
///   resumes it, back to the sentence. Scrubbing scrolls to the paragraph under the thumb.
/// - On regular width the close pill names where the page plays from: a page in a folder plays from that folder (a
///   book, a series, a folder you made), a saved page in no folder from the Library,
///   a page you haven't saved from its site. ⋯ → *Go to <name>* opens the Library at the folder
///   or the Library; for a site, ⋯ → Website opens the page in the browser.
/// - The top bar, 🔖 and ⋯ are the Reader's (decision D24): Aa changes how the page reads; ☝︎
///   then a tap on a paragraph plays from there; 🔖 saves / removes (tap) or files the page
///   (long-press, *Save to Folder…*); ⋯ is the page's menu at `.nowPlaying` (on compact width a
///   system menu, the top group's). Both act through `ArticleActions`, as in the Reader. Voice (an
///   `IconButton`) opens the Voice picker: beside the title in regular width's band, at the compact
///   card's trailing edge.
/// - At the end it stays: the text stays, all in full ink, the player card says "● Finished" (the ring, full)
///   (the one place it shows, where the Reader shows the page's length), ▶ plays it again.
/// - A tap in the middle of the text reads full screen, as in the Reader (`ReadingPage`,
///   `ReadingChrome`): the text still follows the audio, a page turn by a tap stops following as a drag does, and a link
///   in the text opens in the browser.
/// - A pull down closes it, back to exactly what was under it (on regular width the pill or a
///   pull down shrinks it back into the bar). Its full screen is its own: the chrome under it keeps
///   its fold and full screen.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The playing page's reading content, looked up by key when the page changes.
    @State private var content: NowPlayingContent?
    @State private var following = true
    /// Which way the spoken sentence is from the visible text, while not following: Jump to Audio's arrow.
    @State private var spotSide = JumpDirection.up
    @State private var jumpMode = false
    @State private var scrubMap: ReaderScrubMap?
    @State private var scrubPreview: Int?
    @State private var scrollRequest: ReaderScrollRequest?
    /// Compact width: the top group's Aa panel is open.
    @State private var appearanceOpen = false

    /// This showing has had something bound: losing it closes Listen, where opening with nothing
    /// shows *Nothing Playing*.
    @State private var hadSomethingBound = false

    var body: some View {
        Group { screen }
            .onChange(of: speech.nowPlaying != nil, initial: true) { _, bound in
                if bound { hadSomethingBound = true }
            }
    }

    @ViewBuilder
    private var screen: some View {
        if let now = speech.nowPlaying {
            // Only the playing page's content: never the page before's, for a frame, on advance.
            let readerArticle = content?.key == now.articleKey ? content?.readerArticle : nil
            ArticleLookup(key: now.articleKey, canonicalURL: readerArticle?.origin.canonicalURL) { article in
                let actions = ArticleActions(article: article, readerArticle: readerArticle, library: library, shell: shell, speech: speech,
                                             preparedAudio: preparedAudio, follow: follow)
                player(now, actions)
            }
            .environment(\.sheetRisesOnAppear, shell.nowPlayingOpensAt == nil)
            .onChange(of: now.articleKey, initial: true) { _, key in load(key) }
            .task(id: ScrubMapKey(key: now.articleKey, count: speech.document.count)) { await buildScrubMap() }
        } else if hadSomethingBound {
            // The page you heard was removed from the Library or deleted: nothing to show.
            Color.clear.onAppear(perform: shell.hideNowPlaying)
        } else {
            nothingPlaying
        }
    }

    /// Listen opened with nothing bound and nothing played before: a cover like the player's,
    /// pulled down the same way, from anywhere on it. *Open Library* closes it on the Library's home.
    private var nothingPlaying: some View {
        let palette = appearance.palette(accent: AppAppearance.shared.accent)
        let onClose = { [shell, presentation = shell.nowPlayingPresentation] in
            if let presentation { shell.nowPlayingDidClose(presentation) }
        }
        return Sheet(onDismiss: onClose, palette: palette, largePullTargets: sizeClass != .regular) {
            EmptyState(String(localized: "Nothing Playing"),
                       description: Text("Choose an article or book to listen to.")) {
                AddToLibraryTiles(folder: nil)
            }
            .padding(.horizontal, Spacing.pageMargin)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("listenEmpty")
        } content: {
            EmptyView()
        }
    }

    private func player(_ now: NowPlaying, _ actions: ArticleActions) -> some View {
        let palette = appearance.palette(accent: AppAppearance.shared.accent)
        let artwork = now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        let regular = sizeClass == .regular
        let onClose = { [shell, presentation = shell.nowPlayingPresentation] in
            if let presentation { shell.nowPlayingDidClose(presentation) }
        }
        return NowPlayingSheet(
            showing: regular ? .sheet(close: .collapse(playingFromName(now, saved: actions.isSaved)), onClose: onClose)
                : .cover(onClose: onClose),
            playState: speech.playState(of: .article(now.articleKey)),
            showsJumpToAudio: !following && !now.isFinished,
            jumpDirection: spotSide,
            onPlayPause: speech.pressNowPlaying,
            onJumpToAudio: { following = true },
            palette: palette
        ) {
            // The top bar is regular width's; compact Listen's header is the top group (⋯ holds ☝︎).
            TextAppearanceControl()
        } accessory: {
            IconButton(symbol: jumpMode ? Icons.jumpOn : Icons.jump,
                       label: jumpMode ? Verbs.cancelPlayFromParagraph : Verbs.playFromParagraph,
                       identifier: "listenJump", isOn: jumpMode) { withAnimation(Motion.snappy) { jumpMode.toggle() } }
                .disabled(speech.document.isEmpty)
        } banner: {
            VStack(spacing: 0) {
                if !regular {
                    ReadingTopGroup(menu: menuBlocks(now, actions), menuID: "listenMore", appearanceOpen: $appearanceOpen,
                                    carriesGrabber: true)
                }
                if jumpMode { JumpHint { withAnimation(Motion.snappy) { jumpMode = false } } }
            }
        } text: {
            text(now, readerArticle: actions.readerArticle)
        } band: {
            if regular {
                PlayheadReader(speech: speech) { spot in
                    bandContent(now: now, actions: actions, palette: palette, artwork: artwork, spot: spot)
                }
            } else {
                card(now, actions)
            }
        } floating: {
            // The toast floats above the hairline.
            ZStack(alignment: .top) {
                PrepareProgressEdge()
                ShellToastLayer()
            }
        }
    }

    /// Compact width: the player card at Listen's foot.
    private func card(_ now: NowPlaying, _ actions: ArticleActions) -> some View {
        PlayheadReader(speech: speech) { spot in
            let doc = speech.document
            let rate = speech.rateMultiplier
            let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: spot.utf16Offset, rate: rate)
            let source = ArticleRowTitle.lineTwoSource(title: now.title, source: now.source)
            let note = NowPlayingControls.note(of: speech)
            ReaderPlayerCard(
                title: now.lineOne,
                detail: note.map { [$0] } ?? (now.isFinished ? [String(localized: "Finished")]
                    : [source, left > 0 ? ListeningTime.leftLabel(minutes: left) : nil].compactMap { $0 }),
                origin: actions.cardOrigin(title: now.lineOne)
            ) {
                SaveToggleButton(isSaved: actions.isSaved, identifier: "nowPlayingBookmark",
                                 onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder, round: true)
                    .disabled(actions.readerArticle == nil)
            } scrub: {
                playerScrub(spot: spot) { EmptyView() }
            } transport: {
                ListenTransportView(size: .card, speech: speech)
            } leading: {
                SpeedButton(speech: speech)
                    .playerCardTool()
            } trailing: {
                IconButton(symbol: Icons.voice, label: Verbs.voice, identifier: "nowPlayingVoice", round: false) {
                    shell.present(.voice(.article(now.articleKey)))
                }
                .playerCardTool()
            }
        }
    }

    /// Compact width's ⋯ (the top group's): *Play from a Paragraph* (Listen's own: compact Listen has no
    /// top bar for ☝︎), then the page's rows at `.nowPlaying` (`ArticleMenu`), each block a section.
    private func menuBlocks(_ now: NowPlaying, _ actions: ArticleActions) -> [[MenuRow]] {
        let jumpRow = MenuRow(id: "listenJump", title: Verbs.playFromParagraph, icon: Icons.jump,
                              availability: MenuAvailability(when: !speech.document.isEmpty)) {
            withAnimation(Motion.snappy) { jumpMode.toggle() }
        }
        return [[jumpRow]] + ArticleMenu(actions: actions, place: .nowPlaying(actions.goTo(now))).blocks
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
                IconButton(symbol: Icons.voice, label: Verbs.voice, identifier: "nowPlayingVoice") {
                    shell.present(.voice(.article(now.articleKey)))
                }
            }

            // Scrub row
            playerScrub(spot: spot) { SpeedButton(speech: speech) }

            // Notes (buffering, language, etc.)
            NowPlayingControls(speech: speech)

            // Transport: [🔖] [⏮] (⏸) [⏭] [⋯]
            ListenTransportView(
                leading: AnyView(SaveToggleButton(isSaved: actions.isSaved, identifier: "nowPlayingBookmark",
                                                   onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder)
                    .disabled(actions.readerArticle == nil)),
                trailing: AnyView(ReadingPageMoreButton(id: "nowPlayingMore")),
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
                trailing: trailing
            )
        } else {
            // Placeholder: keeps height stable until scrub map builds.
            HStack(spacing: 0) {
                Color.clear.frame(height: Control.small)
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
              let ready = speech.bakeReadyParagraphIndices(articleID: id, paragraphCount: speech.document.count),
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
                       heading: ReaderHeading(title: readerArticle?.title ?? now.title, detail: [], titleHidden: false),
                       finished: now.isFinished, isChapter: now.isChapter, scrubMap: scrubMap,
                       scrubPreview: scrubPreview,
                       jumpMode: jumpMode, scrollRequest: scrollRequest, follows: following,
                       opensAt: shell.nowPlayingOpensAt,
                       onUserScroll: { following = false }, onSpotSide: { spotSide = $0 }, onTap: jump(to:), onOpenLink: { shell.navigate(to: $0) },
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

extension SpeechController {
    /// The paragraph Now Playing's text shows as spoken (on the highlight, all in full ink): the one a
    /// scrub is over while it is dragged, else the playhead; none once the page has finished, so
    /// all of it reads in full ink.
    func spokenParagraph(scrubPreview: Int?) -> Int? {
        guard let now = nowPlaying, !now.isFinished else { return nil }
        return scrubPreview ?? currentParagraphIndex
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
