import SwiftUI

/// Now Playing: what you hear, opened up from the bar (`NowPlayingSheet`). A player on deep jade
/// (light and dark alike), the Reader's serif text in lyrics style under a title card. Presented
/// over everything by the shell; it holds no article of its own: it shows `speech.nowPlaying` and
/// the content its resolver finds.
///
/// - The title card (artwork, title, "site · N min left") scrolls with the text.
/// - The text follows the audio: each new paragraph scrolls near the middle, the spoken
///   paragraph is in full ink and the others dimmed, its sentence underlined. A drag stops
///   following; Back to audio resumes it. Scrubbing scrolls to the paragraph under the thumb.
/// - "Playing from": a saved page plays from the Library (tap: the Library); a page you haven't
///   saved plays from its site (tap: the page in the browser).
/// - ⊕ saves the page (✓ when saved; tap again to remove it).
/// - At the end it stays: the text stays, all in full ink, "✓ Finished", ▶ plays it again.
/// - ⌄ or a pull down shrinks it back into the bar.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell

    /// The reading content of the playing page, resolved by key.
    @State private var article: ReaderArticle?
    /// The page whose content has been looked up (found or not).
    @State private var loadedKey: UUID?
    /// The page's key when it is saved in the Library (⊕ shows ✓).
    @State private var savedKey: UUID?
    @State private var following = true
    @State private var jumpMode = false
    @State private var scrubMap: ReaderScrubMap?
    @State private var scrubPreview: Int?
    @State private var scrollRequest: ReaderScrollRequest?

    var body: some View {
        if let now = speech.nowPlaying {
            NowPlayingSheet(
                playingFrom: savedKey != nil ? "Library" : now.playingFrom.name,
                isSaved: savedKey != nil,
                showsBackToAudio: !following && !now.isFinished,
                onCollapse: { [shell, presentation = shell.nowPlayingPresentation] in
                    if let presentation { shell.nowPlayingDidClose(presentation) }
                },
                onPlayingFrom: { savedKey != nil ? shell.openLibrary() : goToPlayingFrom() },
                onToggleSave: toggleSaved,
                onBackToAudio: { following = true }
            ) {
                text(now)
                    .overlay(alignment: .top) {
                        if jumpMode { JumpHint { jumpMode = false } }
                    }
                    .animation(Motion.snappy, value: jumpMode)
            } controls: {
                NowPlayingControls(
                    speech: speech, scrubMap: scrubMap, detectedLanguage: speech.sessionDetectedLanguage,
                    jumpMode: $jumpMode,
                    more: AnyView(MoreMenuButton(id: "readerMore") { .nowPlaying(menu, perform: perform) }
                        .foregroundStyle(Palette.playerInk)),
                    onScrubPreview: { p in
                        scrubPreview = p
                        if let p { scrollRequest = ReaderScrollRequest(index: p, token: (scrollRequest?.token ?? 0) + 1) }
                    }
                )
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

    private var menu: NowPlayingMenu {
        NowPlayingMenu(canShare: shareURL != nil, canOpenWebsite: websiteURL != nil,
                       showsDebug: speech.developerOptionsEnabled)
    }

    private var websiteURL: URL? {
        guard let url = article?.origin.url, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }

    private var shareURL: URL? {
        guard let url = article?.origin.url, url.isWeb else { return nil }
        return url
    }

    private func perform(_ action: NowPlayingMenu.Action) {
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .listenDebug: speech.showListenDebug = true
        case .favorites: shell.present(.favorites())
        case .history: shell.present(.history)
        case .openWebsite: goToPlayingFrom()
        }
    }

    // MARK: - Actions

    /// "Playing from" a site (and ⋯ → Website): the page in the browser. Playback keeps going.
    private func goToPlayingFrom() {
        guard let websiteURL else { return shell.hideNowPlaying() }
        shell.openWebsite(websiteURL)
    }

    private func load(_ key: UUID) async {
        following = true
        jumpMode = false
        // ⊕ is right from the first frame; the address match below covers older saves.
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

    /// ⊕: saving never touches playback.
    private func toggleSaved() {
        guard let article else { return }
        let saver = ArticleSaveCoordinator(library: library, speech: speech)
        if let savedKey {
            saver.unsave(key: savedKey, canonicalURL: article.origin.canonicalURL)
            self.savedKey = nil
        } else {
            savedKey = saver.save(article)
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

    /// The title card, "site · N min left" (or "✓ Finished"). Replaced in the page only when its
    /// text changes, so once a minute at most while playing.
    private var titleCard: ReadingTopView {
        let doc = speech.document
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: speech.spokenUTF16Offset,
                                             rate: speech.rateMultiplier)
        let detail = finished ? "✓ Finished"
            : [card.source, doc.isEmpty ? "" : "\(left) min left"].filter { !$0.isEmpty }.joined(separator: " · ")
        let letter = card.source.isEmpty ? card.title : card.source
        return ReadingTopView(
            id: [card.title, detail, letter, card.artwork == nil ? "" : "artwork"],
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
            Image(systemName: "hand.tap.fill")
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
