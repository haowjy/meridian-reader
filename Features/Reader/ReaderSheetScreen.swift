import SwiftUI

/// The Reader (`ReaderSheet`): one page for reading, with its own Listen. On compact width it is a
/// destination in the chrome's pill, in place under the bottom chrome, which draws its player card
/// (`ChromeCard`; Aa, Voice, 🔖 and the transport are in it, ☝︎ is a row of ⋯); Library and Browser in
/// the pill leave it to exactly where you were. On regular width it is a sheet over the surface that
/// opened it, closed by the close pill ("‹ Browser", "‹ Library"), the grabber and a pull down. Its
/// top bar, 🔖 and ⋯ are Now Playing's too (decision D24), so Listen turns one into the other with
/// nothing moving. Playback never stops for it.
///
/// - The Reader never shows what you hear (the shell opens Now Playing for that page), so the
///   Now Playing bar above its toolbar is always another page.
/// - Listen reads "▶ Listen  9 min", "▶ Continue  6 min left" (the time lighter, after the title)
///   or "▶ Listen Again", starts at
///   the page's saved spot, and turns the Reader into Now Playing where it was (decision D2).
///   ☝︎ in the top bar, then a tap on a paragraph, listens from that paragraph.
/// - A page part-way through opens with its saved spot's sentence in the middle, underlined;
///   after that the text never scrolls by itself.
/// - 🔖 saves / removes from the Library (tap) or files the page (long-press, *Save to Folder…*: the Move tree);
///   ⋯ is the page's menu (Save / Remove from Library, Move to…, Add to Favorites, Share,
///   Prepare, Prepared Audio; then Settings / Saved / Reader, Reader disabled here, C140). Both act through
///   `ArticleActions`, as in Now Playing.
/// - Aa changes how the page reads (`TextAppearanceControl`), live: left of ☝︎ in the sheet's top bar,
///   in the card's transport on compact width.
/// - Voice (`VoiceChromeButton`), right of the title in the bottom band, opens the page's Voice
///   picker (same as ⋯ › Voice / Settings › Voice's list).
/// - A tap in the middle of the text reads full screen, as in Now Playing (`ReadingPage`,
///   `ReadingChrome`); a link in the text opens in the browser.
///
/// Save / Remove only flips 🔖: the article key is already the saved id (identity v2), so the
/// view and any playing audio are untouched.
struct ReaderSheetScreen: View {
    let state: ReaderSheetState
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var jumpMode = false
    @State private var scroll = ReadingScrollHandle()

    private var readerArticle: ReaderArticle { state.article }

    private var sessionReady: Bool { !readerArticle.document.isEmpty }

    var body: some View {
        // The article's library page, if it has one (saved, played, or a favorite).
        ArticleLookup(key: readerArticle.id, canonicalURL: readerArticle.origin.canonicalURL) { article in
            sheet(ArticleActions(article: article, readerArticle: readerArticle, library: library, shell: shell, speech: speech,
                              preparedAudio: preparedAudio, follow: follow))
        }
    }

    private func sheet(_ actions: ArticleActions) -> some View {
        let start = listenStart(actions.article)
        let listen = readerArticle.listenLabel(from: start, finished: actions.article?.finishedAt != nil,
                                               rate: speech.rateMultiplier)
        let palette = appearance.palette(accent: AppAppearance.shared.accent)
        let isFinished = actions.article?.finishedAt != nil
        let timeDetail = isFinished ? String(localized: "Finished") : listen.detail
        let compactCard = sizeClass == .regular ? nil
            : card(actions, start: start, detail: isFinished ? timeDetail : detail(listen.detail).joined(separator: " · "))
        let playerTitle = ArticleRowTitle.lineOne(title: readerArticle.title, source: readerArticle.sourceLabel,
                                                  address: readerArticle.origin.canonicalURL)
        let playerLetter = ArticleRowTitle.artworkLetter(title: readerArticle.title, source: readerArticle.sourceLabel,
                                                         address: readerArticle.origin.canonicalURL)
        return ReaderSheet(
            showing: shell.readingShowing(
                regular: sizeClass == .regular, close: .back(state.origin.backTitle),
                onClose: { [shell, presentation = state.presentation] in shell.readerDidClose(presentation) }),
            listenState: speech.playState(of: .article(readerArticle.id)),
            onListen: { self.listen(from: nil, start: start) },
            palette: palette
        ) {
            TextAppearanceControl()
        } accessory: {
            JumpModeButton(isOn: jumpMode) { withAnimation(Motion.snappy) { jumpMode.toggle() } }
                .disabled(!sessionReady)
        } banner: {
            if jumpMode { JumpHint { withAnimation(Motion.snappy) { jumpMode = false } } }
        } text: {
            text(start, status: listen.detail, chapter: actions.article?.isChapter == true)
        } band: {
            VStack(spacing: Spacing.xs) {
                // Another article playing: show Now Playing bar above the controls.
                if let nowPlaying = speech.nowPlaying, nowPlaying.articleKey != readerArticle.id {
                    NowPlayingBarView(speech: speech)
                }
                // Title row: artwork + title/source + bookmark
                HStack(spacing: Spacing.s) {
                    ArtworkTile(letter: playerLetter.isEmpty ? playerTitle : playerLetter,
                                size: PlayerCard.artworkSize)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(playerTitle)
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
                    // Voice, aligned right of the title (same picker as ⋯ › Voice / Settings › Voice).
                    VoiceChromeButton(identifier: "readerVoice") {
                        shell.present(.voice(.article(readerArticle.id)))
                    }
                    SaveToggleButton(isSaved: actions.isSaved, identifier: "readerBookmark",
                                     onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder)
                        .frame(width: BottomChrome.minTapTarget)
                        // Hug the trailing content edge (scrubber end) while keeping the 44 pt hit area.
                        .padding(.trailing, -(BottomChrome.minTapTarget - BottomChrome.iconSize) / 2)
                }
                // Scrub track (thin, no capsule, full width)
                readerScrubTrack
                // Transport: [1x] [⏮] (▶) [⏭] [...]
                NowPlayingTransport(state: speech.playState(of: .article(readerArticle.id)),
                                    canSkipBack: false, canSkipForward: false,
                                    onSkipBack: {}, onSkipForward: {},
                                    onPlayPause: { self.listen(from: nil, start: start) }) {
                    SpeedButton(speech: speech)
                } more: {
                    // Compact width: the chrome's ⋯ (`ReadingPageMoreButton`) is the page's menu.
                    if sizeClass == .regular {
                        ReadingPageMoreButton(id: "readerMore").foregroundStyle(palette.ink)
                    } else {
                        Color.clear.frame(height: BottomChrome.rowHeight)
                    }
                }
            }
            .frame(maxWidth: sizeClass == .regular ? RegularLayout.playerClusterWidth : .infinity)
            .frame(maxWidth: .infinity)
        } floating: {
            // The toast floats above the hairline.
            ZStack(alignment: .top) {
                PrepareProgressEdge()
                ShellToastLayer()
            }
        }
        .chromeCard(compactCard)
        .task(id: WarmKey(id: readerArticle.id, count: readerArticle.document.count)) {
            speech.warmUp(readerArticle, from: start, saved: actions.isSaved)
        }
    }

    /// Compact width: the card the chrome draws above row 2, and ⋯'s row for ☝︎.
    private func card(_ actions: ArticleActions, start: ListenSpot, detail: String?) -> ChromeCard {
        let document = readerArticle.document
        let rate = speech.rateMultiplier
        let heard = document.isEmpty ? 0 : document.startUTF16Offset(forParagraph: start.paragraph) + start.utf16Offset
        let left = ListeningTime.minutes(utf16Length: max(0, document.utf16Length - heard), rate: rate)
        let title = ArticleRowTitle.lineOne(title: readerArticle.title, source: readerArticle.sourceLabel,
                                            address: readerArticle.origin.canonicalURL)
        let letter = ArticleRowTitle.artworkLetter(title: readerArticle.title, source: readerArticle.sourceLabel,
                                                   address: readerArticle.origin.canonicalURL)
        let view = ReaderPlayerCard(
            title: title, detail: detail, artworkLetter: letter, playState: speech.playState(of: .article(readerArticle.id)),
            elapsed: ListeningTime.clock(seconds: ListeningTime.secondsHeard(in: document, toUTF16Offset: heard, rate: rate)),
            timeLeft: "−" + ListeningTime.label(minutes: left), canSkip: false, onSkipBack: {}, onSkipForward: {},
            onPlayPause: { self.listen(from: nil, start: start) }
        ) {
            VoiceChromeButton(identifier: "readerVoice") { shell.present(.voice(.article(readerArticle.id))) }
        } save: {
            SaveToggleButton(isSaved: actions.isSaved, identifier: "readerBookmark",
                             onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder)
        } scrub: {
            readerScrubTrack
        } appearance: {
            TextAppearanceControl(arrowEdge: .bottom)
        } speed: {
            SpeedButton(speech: speech)
        }
        let jump = MenuRow(id: "listenJump", title: Verbs.playFromParagraph, icon: Icons.jump,
                           availability: MenuAvailability(when: sessionReady)) {
            withAnimation(Motion.snappy) { jumpMode.toggle() }
        }
        return ChromeCard(content: AnyView(view), menuRows: [jump])
    }

    /// A thin scrub track at position 0 for the Reader (before Listen starts).
    private var readerScrubTrack: some View {
        let paragraphs = readerArticle.document.paragraphs
        return Group {
            if !paragraphs.isEmpty {
                let map = ReaderScrubMap(paragraphs: paragraphs, sentences: false)
                ReaderScrubRow(map: map, position: 0, onScrubPreview: { _ in },
                               onScrubCommit: { _ in }, isCapsule: false) {
                    EmptyView()
                }
            } else {
                ScrubTrack(value: 0).frame(height: 20)
            }
        }
    }

    /// Where Listen starts: the page's saved spot, or its top once it is finished.
    private func listenStart(_ article: Article?) -> ListenSpot {
        article?.listenStart ?? ListenSpot(paragraph: readerArticle.resumeParagraph)
    }

    // MARK: - Text

    @ViewBuilder
    private func text(_ start: ListenSpot, status: String?, chapter: Bool) -> some View {
        HTMLReadingView(html: readerArticle.readingHTML, heading: ReaderHeading(title: readerArticle.title, detail: detail(status), titleHidden: true),
                        activeParagraphIndex: nil, sentence: savedSentence(start), jumpMode: jumpMode,
                        opensAtSentence: true, scrollHandle: scroll, onOpenLink: shell.navigate(to:),
                        pageTimeLeft: { [document = readerArticle.document, rate = speech.rateMultiplier] in
                            ListeningTime.leftLabel(in: document, paragraph: $0, offset: $1, rate: rate,
                                                    chapter: chapter)
                        },
                        onPlaySelection: { paragraph, offset in
                            guard let spot = ListenSpot.fromSelection(in: readerArticle.document, paragraph: paragraph,
                                                                      offset: offset) else { return }
                            listen(at: spot)
                        }) { index in
            if jumpMode { listen(from: index, start: start) }
        }
        .regularReadableMeasure(isRegular: sizeClass == .regular)
    }

    /// The sentence at the page's saved listening spot, while it is part-way through: the text
    /// opens with it in the middle, underlined, where Continue starts.
    private func savedSentence(_ start: ListenSpot) -> ReaderSentence? {
        guard start.isPartWay else { return nil }
        return ReaderSentence(in: readerArticle.document, paragraph: start.paragraph, utf16Offset: start.utf16Offset)
    }

    private var totalLength: Int {
        sessionReady ? readerArticle.document.utf16Length : readerArticle.plainText.utf16.count
    }

    /// The source, then what Listen's detail says, as a row's second line does: the length
    /// before a start ("9 min"), the time left part-way ("6 min left"); a finished page (Listen
    /// Again, no detail) its length. ["example.org", "6 min left"].
    private func detail(_ status: String?) -> [String] {
        let minutes = ListeningTime.minutes(utf16Length: totalLength, rate: speech.rateMultiplier)
        let length = minutes > 0 ? ListeningTime.label(minutes: minutes) : ""
        return [readerArticle.sourceLabel, status ?? length].filter { !$0.isEmpty }
    }

    // MARK: - Actions

    /// Listen (`paragraph` nil: from the page's saved spot, `start`; a finished page from the
    /// start), or ☝︎ then a tap on a paragraph. The page becomes what you hear, and the Reader
    /// turns into Now Playing at the same scroll position.
    private func listen(from paragraph: Int?, start: ListenSpot) {
        guard sessionReady else { return }
        jumpMode = false
        let handOver = scroll.handOver
        speech.listen(to: readerArticle, at: paragraph.map { ListenSpot(paragraph: $0) } ?? start)
        shell.turnReaderIntoNowPlaying(handOver: handOver)
    }

    /// *Play from Here* on a selection (C109): the page plays from that spot, as Listen does.
    private func listen(at spot: ListenSpot) {
        guard sessionReady else { return }
        jumpMode = false
        let handOver = scroll.handOver
        speech.listen(to: readerArticle, at: spot)
        shell.turnReaderIntoNowPlaying(handOver: handOver)
    }

    private struct WarmKey: Hashable {
        let id: UUID
        let count: Int
    }
}
