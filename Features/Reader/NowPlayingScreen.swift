import SwiftUI

/// Now Playing: what you hear, opened up from the bar (`NowPlayingSheet`). The Reader's page in
/// the same reading theme and type, under a title card: the spoken paragraph highlighted in full
/// ink, the others dimmed. Presented over everything by the shell; it holds no article of its
/// own: it shows `speech.nowPlaying` and the playing page's content, looked up in the library by
/// its key.
///
/// - The title card (artwork, title, the site and time left) scrolls with the text.
/// - The text follows the audio: it opens with the spoken sentence near the middle and keeps it
///   there (each new paragraph, a long paragraph's sentence leaving the screen); the spoken
///   paragraph is highlighted in full ink and the others dimmed, its sentence underlined. A drag stops
///   following; Jump to Audio resumes it, back to the sentence. Scrubbing scrolls to the
///   paragraph under the thumb.
/// - The close pill names where the page plays from: a page in a folder plays from that folder (a
///   book, a series, Favorites, a folder you made), a saved page in no folder from the Library,
///   a page you haven't saved from its site. ⋯ → *Go to <name>* opens the Library at the folder
///   or the Library; for a site, ⋯ → Website opens the page in the browser.
/// - The top bar, 🔖 and ⋯ are the Reader's (decision D24): Aa changes how the page reads; ☝︎
///   then a tap on a paragraph plays from there; 🔖 saves / unsaves (tap) or files the page
///   (long-press, *Save to Folder…*); ⋯ is the Reader's menu. Both act through `PageActions`, as
///   in the Reader.
/// - At the end it stays: the text stays, all in full ink, the title card says "✓ Finished"
///   (the one place it shows, where the Reader shows the page's length), ▶ plays it again.
/// - The pill or a pull down shrinks it back into the bar.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(DownloadCenter.self) private var downloads
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
            let article = content?.key == now.pageKey ? content?.article : nil
            PageLookup(key: now.pageKey, canonicalURL: article?.origin.canonicalURL) { page in
                player(now, PageActions(article: article, page: page, library: library, shell: shell, speech: speech,
                                        downloads: downloads))
            }
            .environment(\.sheetRisesOnAppear, shell.nowPlayingOpensAt == nil)
            .onChange(of: now.pageKey, initial: true) { _, key in load(key) }
            .task(id: ScrubMapKey(key: now.pageKey, count: speech.document.count)) { await buildScrubMap() }
        } else {
            // Nothing is bound (crash resume found nothing to play): nothing to show.
            Color.clear.onAppear(perform: shell.hideNowPlaying)
        }
    }

    private func player(_ now: NowPlaying, _ actions: PageActions) -> some View {
        NowPlayingSheet(
            playingFrom: playingFromName(now, saved: actions.isSaved),
            showsJumpToAudio: !following && !now.isFinished,
            onCollapse: { [shell, presentation = shell.nowPlayingPresentation] in
                if let presentation { shell.nowPlayingDidClose(presentation) }
            },
            onJumpToAudio: { following = true },
            palette: appearance.palette(accent: AppAppearance.shared.accent)
        ) {
            TextAppearanceControl()
        } accessory: {
            JumpModeButton(isOn: jumpMode) { jumpMode.toggle() }
                .disabled(speech.document.isEmpty)
        } text: {
            text(now, article: actions.article)
                .jumpHint(jumpMode) { jumpMode = false }
                .animation(Motion.snappy, value: jumpMode)
        } controls: {
            NowPlayingControls(
                speech: speech, scrubMap: scrubMap, detectedLanguage: speech.sessionDetectedLanguage,
                save: AnyView(SaveToggleButton(isSaved: actions.isSaved, identifier: "nowPlayingBookmark",
                                               onToggle: actions.toggleSaved, onSaveToFolder: actions.saveToFolder)
                    .disabled(actions.article == nil)),
                more: AnyView(MoreMenuButton(id: "nowPlayingMore") {
                    .reader(actions.readerMenu(goTo: goToPlace(now, saved: actions.isSaved)),
                            perform: { actions.perform($0) { goTo(now) } })
                }),
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
    }

    // MARK: - Text

    @ViewBuilder
    private func text(_ now: NowPlaying, article: ReaderArticle?) -> some View {
        if let html = readingHTML(now, article: article) {
            SpokenText(speech: speech, html: html,
                       card: TitleCardContent(title: article?.title ?? now.title, source: now.source,
                                              artwork: now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))),
                       finished: now.isFinished, scrubMap: scrubMap, scrubPreview: scrubPreview,
                       jumpMode: jumpMode, scrollRequest: scrollRequest, follows: following,
                       opensAt: shell.nowPlayingOpensAt,
                       onUserScroll: { following = false }, onTap: jump(to:))
        } else {
            appearance.palette(accent: AppAppearance.shared.accent).background
        }
    }

    /// The page's reading HTML; for a plain-text article, or content that can't be found, the
    /// session's paragraphs as HTML, so every page reads, follows and underlines the same way.
    /// Nothing until the page's content has been looked up.
    private func readingHTML(_ now: NowPlaying, article: ReaderArticle?) -> String? {
        if let html = article?.displayHTML, html.contains(where: { !$0.isWhitespace }) { return html }
        guard content?.key == now.pageKey, !speech.document.isEmpty else { return nil }
        return speech.document.paragraphsHTML
    }

    // MARK: - Actions

    private func playingFromName(_ now: NowPlaying, saved: Bool) -> String {
        if case .folder = now.playingFrom { return now.playingFrom.name }
        return saved ? String(localized: "Library") : now.playingFrom.name
    }

    /// ⋯ → *Go to*: the folder the page plays from, or the Library for a saved page in none; nil
    /// for a page that plays from its site (⋯ → Website opens it).
    private func goToPlace(_ now: NowPlaying, saved: Bool) -> ReaderMenu.Place? {
        if case .folder = now.playingFrom { return ReaderMenu.Place(name: now.playingFrom.name, symbol: Icons.folder) }
        return saved ? ReaderMenu.Place(name: String(localized: "Library"), symbol: Icons.library) : nil
    }

    /// ⋯ → *Go to*: the Library at the folder, or the Library's home. Playback keeps going.
    private func goTo(_ now: NowPlaying) {
        if case .folder(let id, _) = now.playingFrom, let folder = library.folder(id: id) {
            shell.showLibrary(at: library.path(to: folder))
        } else {
            shell.showLibrary(at: [])
        }
    }

    /// The playing page changed: its content, and the text following the audio again.
    private func load(_ key: UUID) {
        following = true
        jumpMode = false
        content = NowPlayingContent(key: key, article: library.nowPlayingContent(for: key))
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

/// The reading content looked up for a playing page (nil: it can't be found).
private struct NowPlayingContent {
    let key: UUID
    let article: ReaderArticle?
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

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let paragraph = speech.currentParagraphIndex
        HTMLReadingView(
            html: html,
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
        let palette = reading ?? .app
        return ReadingTopView(
            id: [card.title, detail.joined(separator: "\n"), letter, card.artwork == nil ? "" : "artwork",
                 palette.theme.rawValue, AppAppearance.shared.accent.rawValue],
            view: AnyView(TitleCard(title: card.title, detail: detail, artwork: card.artwork, artworkLetter: letter,
                                    palette: palette))
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

/// "Tap a paragraph to play from there", docked above the text while ☝︎ is on (`jumpHint`), its
/// capsule at the page margin like the text under it, on the reading page's card colour.
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
            Button("Cancel", action: onCancel)
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

extension View {
    /// The Jump hint above the reading text while ☝︎ is on: the text moves down by the hint's
    /// height, so the hint never covers the title or the first line.
    func jumpHint(_ isOn: Bool, onCancel: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if isOn { JumpHint(onCancel: onCancel) }
            self
        }
    }
}
