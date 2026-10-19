import SwiftUI

/// The Reader sheet (`ReaderSheet`): one page for reading, over the surface that opened it, with
/// its own Listen. The close pill names what is underneath ("‹ Browser", "‹ Library"); it, the
/// grabber and a pull down close it to exactly where you were. Its top bar, 🔖 and ⋯ are Now
/// Playing's too (decision D24), so Listen turns one into the other with nothing moving. Playback never stops for it.
///
/// - The Reader never shows what you hear (the shell opens Now Playing for that page), so the
///   Now Playing bar above its toolbar is always another page.
/// - Listen reads "▶ Listen  9 min", "▶ Resume  6 min left" (the time lighter, after the title)
///   or "▶ Listen Again", starts at
///   the page's saved spot, and turns the Reader into Now Playing where it was (decision D2).
///   ☝︎ in the top bar, then a tap on a paragraph, listens from that paragraph.
/// - A page part-way through opens with its saved spot's sentence in the middle, underlined;
///   after that the text never scrolls by itself.
/// - 🔖 saves / removes from the Library (tap) or files the page (long-press, *Save to Folder…*: the Move tree);
///   ⋯ is the page's menu (Save / Remove from Library, Move to…, Add to Favorites, Share,
///   Download, Downloads, Settings; Favorites / History / Website). Both act through
///   `PageActions`, as in Now Playing.
/// - Aa, left of ☝︎, changes how the page reads (`TextAppearanceControl`), live.
/// - Scrolling down reads full screen, as in Now Playing (`ReaderSheet`, `ReadingChrome`); a link
///   in the text opens in the browser.
///
/// Save / Remove only flips 🔖: the article key is already the saved id (identity v2), so the
/// view and any playing audio are untouched.
struct ReaderSheetScreen: View {
    let state: ReaderSheetState
    @Bindable var speech: SpeechController

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(DownloadCenter.self) private var downloads
    @Environment(\.readingAppearance) private var appearance
    @State private var jumpMode = false
    @State private var scroll = ReadingScrollHandle()

    private var article: ReaderArticle { state.article }

    private var sessionReady: Bool { !article.document.isEmpty }

    var body: some View {
        // The article's library page, if it has one (saved, played, or a favorite).
        PageLookup(key: article.id, canonicalURL: article.origin.canonicalURL) { page in
            sheet(PageActions(article: article, page: page, library: library, shell: shell, speech: speech,
                              downloads: downloads, follow: follow))
        }
    }

    private func sheet(_ actions: PageActions) -> some View {
        let start = listenStart(actions.page)
        let listen = listenLabel(start, finished: actions.page?.finishedAt != nil)
        return ReaderSheet(
            backTitle: state.origin.backTitle,
            listenTitle: listen.title,
            listenDetail: listen.detail,
            listenState: speech.playState(of: .page(article.id)),
            isSaved: actions.isSaved,
            onClose: { [shell, presentation = state.presentation] in shell.readerDidClose(presentation) },
            onListen: { self.listen(from: nil, start: start) },
            onToggleSave: actions.toggleSaved,
            onSaveToFolder: actions.saveToFolder,
            palette: appearance.palette(accent: AppAppearance.shared.accent)
        ) {
            TextAppearanceControl()
        } accessory: {
            JumpModeButton(isOn: jumpMode) { withAnimation(Motion.snappy) { jumpMode.toggle() } }
                .disabled(!sessionReady)
        } banner: {
            if jumpMode { JumpHint { withAnimation(Motion.snappy) { jumpMode = false } } }
        } text: {
            text(start)
        } bar: {
            NowPlayingBarView(speech: speech)
        } more: {
            MoreMenuButton(id: "readerMore") { .reader(actions.readerMenu, perform: { actions.perform($0) }) }
        } floating: {
            // The line at the band's top edge; the toast floats above it.
            ZStack(alignment: .top) {
                DownloadProgressEdge()
                ShellToastLayer()
            }
        }
        .task(id: WarmKey(id: article.id, count: article.document.count)) {
            prepareListen(from: start, saved: actions.isSaved)
        }
    }

    /// Where Listen starts: the page's saved spot, or its top once it is finished.
    private func listenStart(_ page: Page?) -> ListenSpot {
        page?.listenStart ?? ListenSpot(paragraph: article.resumeParagraph)
    }

    // MARK: - Text

    @ViewBuilder
    private func text(_ start: ListenSpot) -> some View {
        HTMLReadingView(html: article.readingHTML, heading: ReaderHeading(title: article.title, detail: detail),
                        activeParagraphIndex: nil, sentence: savedSentence(start), jumpMode: jumpMode,
                        opensAtSentence: true, scrollHandle: scroll, onOpenLink: shell.navigate(to:)) { index in
            if jumpMode { listen(from: index, start: start) }
        }
    }

    /// The sentence at the page's saved listening spot, while it is part-way through: the text
    /// opens with it in the middle, underlined, where Resume starts.
    private func savedSentence(_ start: ListenSpot) -> ReaderSentence? {
        guard start.isPartWay else { return nil }
        return ReaderSentence(in: article.document, paragraph: start.paragraph, utf16Offset: start.utf16Offset)
    }

    private var totalLength: Int {
        sessionReady ? article.document.utf16Length : article.plainText.utf16.count
    }

    /// The source and the length at the current speed, as separate parts: ["example.org", "9 min"].
    private var detail: [String] {
        let minutes = ListeningTime.minutes(utf16Length: totalLength, rate: speech.rateMultiplier)
        return [article.sourceLabel, minutes > 0 ? ListeningTime.label(minutes: minutes) : ""].filter { !$0.isEmpty }
    }

    /// Listen's title and the lighter time after it, at the current speed: "Listen" "9 min",
    /// "Resume" "6 min left", "Listen Again".
    private func listenLabel(_ start: ListenSpot, finished: Bool) -> (title: String, detail: String?) {
        if finished { return (String(localized: "Listen Again"), nil) }
        let doc = article.document
        if start.isPartWay, doc.paragraphs.indices.contains(start.paragraph) {
            let at = start.resolved(in: doc).utf16Offset
            let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: at, rate: speech.rateMultiplier)
            return (String(localized: "Resume"), ListeningTime.leftLabel(minutes: left))
        }
        return (String(localized: "Listen"),
                ListeningTime.label(minutes: ListeningTime.minutes(utf16Length: totalLength, rate: speech.rateMultiplier)))
    }

    // MARK: - Actions

    /// Listen (`paragraph` nil: from the page's saved spot, `start`; a finished page from the
    /// start), or ☝︎ then a tap on a paragraph. The page becomes what you hear, and the Reader
    /// turns into Now Playing at the same scroll position.
    private func listen(from paragraph: Int?, start: ListenSpot) {
        guard sessionReady else { return }
        jumpMode = false
        let handOver = scroll.handOver
        speech.listen(to: article, at: paragraph.map { ListenSpot(paragraph: $0) } ?? start)
        shell.turnReaderIntoNowPlaying(handOver: handOver)
    }

    /// Identity alignment + the first audio for this article, so Listen starts quickly. The Reader
    /// never shows what is playing, so this never touches live playback.
    private func prepareListen(from start: ListenSpot, saved: Bool) {
        guard sessionReady else { return }
        let paragraphs = article.document.paragraphs
        ListenTimingLog.log("reader_open", [
            "key": ListenTimingLog.shortKey(article.id),
            "paragraphs": paragraphs.count,
            "chars": paragraphs.reduce(0) { $0 + $1.count },
            "resume_p": start.paragraph,
            "local_ready": speech.localTTS.usesLocalEngine,
            "saved": saved,
        ])
        speech.localTTS.prepareListenIdentity(
            key: article.id,
            paragraphs: paragraphs,
            trustedParagraphs: article.trustedParagraphs,
            legacyKeys: article.legacyCacheKeys,
            isLivePlayback: false
        )
        speech.localTTS.openArticle(cacheKey: article.id, paragraphs: paragraphs, from: start.paragraph,
                                    isEphemeral: !saved)
    }

    private struct WarmKey: Hashable {
        let id: UUID
        let count: Int
    }
}
