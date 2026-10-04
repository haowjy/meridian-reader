import SwiftUI
import SwiftData

/// Now Playing: what you hear, opened up from the bar (`NowPlayingSheet`). Same paper and serif as
/// the Reader; its chrome is the player's. Presented over everything by the shell; it holds no
/// article of its own: it shows `speech.nowPlaying` and the content its resolver finds.
///
/// - The text follows the audio: each new paragraph scrolls near the middle, the spoken
///   paragraph is tinted and its sentence underlined. A drag stops following; Back to audio
///   resumes it. Scrubbing scrolls to the paragraph under the thumb.
/// - "Playing from <site>" closes Now Playing and shows the page in the browser.
/// - ⊕ saves the page (✓ when saved; tap again to remove it).
/// - At the end it stays: the text stays, the tint goes, "✓ Finished", ▶ plays it again.
/// - ⌄ or a pull down shrinks it back into the bar.
struct NowPlayingScreen: View {
    @Bindable var speech: SpeechController

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellState.self) private var shell

    /// The reading content of the playing page, resolved by key.
    @State private var article: ReaderArticle?
    /// The page whose content has been looked up (found or not).
    @State private var loadedKey: UUID?
    /// The saved row's id when the page is saved (⊕ shows ✓).
    @State private var savedID: UUID?
    @State private var following = true
    @State private var jumpMode = false
    @State private var scrubMap: ReaderScrubMap?
    @State private var scrubPreview: Int?
    @State private var scrollRequest: ReaderScrollRequest?

    var body: some View {
        if let now = speech.nowPlaying {
            NowPlayingSheet(
                playingFrom: now.playingFrom.name,
                isSaved: savedID != nil,
                showsBackToAudio: !following && !now.isFinished,
                onCollapse: shell.hideNowPlaying,
                onPlayingFrom: { goToPlayingFrom() },
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
                        .foregroundStyle(Palette.ink)),
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
        if let article, article.displayHTML.contains(where: { !$0.isWhitespace }) {
            SpokenText(speech: speech, html: article.displayHTML,
                       heading: ReaderHeading(title: article.title, detail: detail(now)),
                       finished: now.isFinished, scrubMap: scrubMap, scrubPreview: scrubPreview,
                       jumpMode: jumpMode, scrollRequest: scrollRequest, follows: following,
                       opensAt: shell.nowPlayingOpensAt,
                       onUserScroll: { following = false }, onTap: jump(to:))
        } else if loadedKey == now.pageKey, !speech.document.isEmpty {
            // No reading HTML (a plain-text article, or content that can't be found): the paragraphs.
            ParagraphReadingView(
                title: now.title,
                document: speech.document,
                activeParagraphIndex: now.isFinished ? nil : (scrubPreview ?? speech.currentParagraphIndex),
                jumpMode: jumpMode,
                scrollRequest: scrollRequest,
                onTapParagraph: jump(to:)
            )
        } else {
            Palette.paper
        }
    }

    private func detail(_ now: NowPlaying) -> String {
        let minutes = ListeningTime.minutes(utf16Length: speech.document.utf16Length)
        return [now.source, minutes > 0 ? "\(minutes) min" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - ⋯

    private var menu: NowPlayingMenu {
        NowPlayingMenu(canShare: shareURL != nil, canOpenWebsite: websiteURL != nil,
                       showsDebug: speech.developerOptionsEnabled)
    }

    private var websiteURL: URL? {
        guard let url = article?.url, url.scheme != nil, url.host?.isEmpty == false else { return nil }
        return url
    }

    private var shareURL: URL? {
        guard let url = article?.url, url.isWeb else { return nil }
        return url
    }

    private func perform(_ action: NowPlayingMenu.Action) {
        switch action {
        case .voiceSettings: shell.present(.voiceSettings)
        case .share: if let shareURL { shell.present(.share(shareURL)) }
        case .listenDebug: speech.showListenDebug = true
        case .bookmarks: shell.present(.bookmarks)
        case .saved: shell.openLibrary()
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
        // ⊕ is right from the first frame; the canonical-URL match below covers older saves.
        savedID = ArticleLibrary.savedArticle(id: key, in: modelContext)?.id
        let loaded = await speech.nowPlayingContent()
        guard speech.activeSessionID == key else { return }
        article = loaded
        loadedKey = key
        savedID = savedRowID(for: loaded) ?? savedID
    }

    private func savedRowID(for article: ReaderArticle?) -> UUID? {
        guard let article else { return nil }
        return (ArticleLibrary.savedArticle(id: article.id, in: modelContext)
            ?? ArticleLibrary.savedArticle(canonicalURL: article.canonicalURL, in: modelContext))?.id
    }

    /// ⊕: saving never touches playback.
    private func toggleSaved() {
        guard let article else { return }
        let saver = ArticleSaveCoordinator(context: modelContext, speech: speech)
        if let savedID {
            saver.unsave(id: savedID, canonicalURL: article.canonicalURL)
            self.savedID = nil
        } else {
            savedID = saver.save(article)
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

/// The text with the spoken paragraph tinted and its sentence underlined. Its own view because the
/// sentence follows the live offset, which moves several times a second: only this leaf (and the
/// web view's bridge, which sends only changes) redraws for it.
private struct SpokenText: View {
    let speech: SpeechController
    let html: String
    let heading: ReaderHeading
    let finished: Bool
    let scrubMap: ReaderScrubMap?
    let scrubPreview: Int?
    let jumpMode: Bool
    let scrollRequest: ReaderScrollRequest?
    let follows: Bool
    let opensAt: CGFloat?
    let onUserScroll: () -> Void
    let onTap: (Int) -> Void

    var body: some View {
        let paragraph = speech.currentParagraphIndex
        HTMLReadingView(
            html: html,
            heading: heading,
            activeParagraphIndex: finished ? nil : (scrubPreview ?? paragraph),
            sentence: finished || scrubPreview != nil ? nil : sentence(paragraph),
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: follows && !finished,
            opensAt: opensAt,
            onUserScroll: onUserScroll,
            onTapParagraph: onTap
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

/// "Tap a paragraph to play from there", floating over the top of the text while ☝︎ is on.
struct JumpHint: View {
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal, Spacing.s)
        .padding(.top, Spacing.xs)
        .transition(.slideAndFade(from: .top, reduceMotion: reduceMotion))
    }
}
