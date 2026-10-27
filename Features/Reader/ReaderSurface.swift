import SwiftUI

/// The Library's Read and the Browser's reader mode on compact width: an article's text in place
/// of the page under the bottom chrome, through the same reading page as the Reader and Now
/// Playing (`ReadingPage`, in place). So the text reads as the Appearance setting says (Pages or
/// Scroll), with the footer, a tap in the middle for full screen, and *Play from Here* on a
/// selection; the text opens at the page's saved listening spot, underlined.
///
/// What is around the text is the chrome's: the Library's capsule (Aa, Listen) or the Browser's
/// round Listen control (`ReaderListenCapsule`, `ReaderListenButton`), and ‹. Listen plays the page
/// and raises Now Playing (the Listen destination), so this surface ends there; coming back with
/// ‹ shows it again. While the page is what you hear its text shows the playhead as Now Playing's
/// does (the spoken paragraph in full ink, its sentence underlined, the text following the audio)
/// with Jump to Audio after a drag. Links navigate the browser. The title and source line are the
/// first thing in the text (no card shows them).
struct ReaderSurface: View {
    let article: ReaderArticle
    let speech: SpeechController
    /// Another layer is over it (the Library, Now Playing, a sheet): it stays mounted for its place
    /// in the text, but leaves the status bar, the chrome's fold and the audio-following to what shows.
    let covered: Bool
    /// The left-edge swipe: what the chrome's ‹ does (the web view's own swipe sits under this
    /// view, out of reach). nil when there is nothing to go back to.
    let onEdgeSwipeBack: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.readingAppearance) private var appearance

    @State private var chrome = ReadingChrome()
    /// The text keeps the spoken sentence in view (while the page is what you hear); a drag stops it.
    @State private var following = true
    @State private var spotSide = JumpDirection.up
    @State private var scrubMap: ReaderScrubMap?

    private var palette: ReadingPalette { appearance.palette(accent: AppAppearance.shared.accent) }

    var body: some View {
        let listen = QuickListen(article: article, speech: speech, shell: shell, library: library)
        let hearing = listen.isHearing
        let finished = hearing && speech.nowPlaying?.isFinished == true
        let place = inPlace
        ReadingPage(showing: .inPlace(place), chrome: chrome, palette: palette) {
            EmptyView()
        } banner: {
            EmptyView()
        } text: {
            text(listen, hearing: hearing, finished: finished)
        } band: {
            EmptyView()
        } floating: {
            EmptyView()
        } overText: {
            ZStack {
                // The clearance is measured from the top of the chrome's box; its rows start
                // `topPadding` below it, so the button comes down that much to sit 12 above them.
                JumpToAudioButton(chrome: chrome, awayFromAudio: hearing && !following && !finished,
                                  direction: spotSide) { following = true }
                    .offset(y: ChromeMetrics.topPadding)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                FloatingPlayButton(state: speech.playState(of: .article(hearing ? speech.activeSessionID ?? article.id : article.id)),
                                   action: hearing ? speech.pressNowPlaying : listen.press)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .overlay(alignment: .leading) { edgeSwipe }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inPlaceReader")
        .onChange(of: hearing) { _, _ in following = true }
        .task(id: WarmKey(id: article.id, count: article.document.count)) { listen.warmUp() }
        .task(id: ScrubKey(hearing: hearing, count: speech.document.count)) { await buildScrubMap(hearing) }
    }

    /// The shell's in-place reading, silent while covered: a hidden reader's follow moves must not
    /// become the Library's fold anchor.
    private var inPlace: ReadingInPlace {
        var place = shell.pageReadingInPlace
        guard covered else { return place }
        place.scrolled = { _ in }
        place.anchored = { _ in }
        place.covered = true
        return place
    }

    // MARK: - Text

    private func text(_ listen: QuickListen, hearing: Bool, finished: Bool) -> some View {
        let start = listen.start
        return SpokenText(
            speech: speech, html: article.readingHTML,
            heading: ReaderHeading(title: article.title, detail: detail(listen, hearing: hearing)),
            spoken: hearing, document: hearing ? speech.document : article.document,
            finished: finished, scrubMap: hearing ? scrubMap : nil,
            savedSentence: hearing ? nil : savedSentence(start),
            follows: following && !covered, opensAtSentence: !hearing,
            onUserScroll: { following = false }, onSpotSide: { spotSide = $0 },
            onTap: { _ in }, onOpenLink: shell.navigate(to:),
            onPlaySelection: { playFromSelection(listen, hearing: hearing, paragraph: $0, offset: $1) })
    }

    /// The source, then the length before a start ("9 min") or the time left part-way ("6 min left"), as a row's second line says.
    private func detail(_ listen: QuickListen, hearing: Bool) -> [String] {
        let length = article.document.isEmpty ? article.plainText.utf16.count : article.document.utf16Length
        let minutes = ListeningTime.minutes(utf16Length: length, rate: speech.rateMultiplier)
        let total = minutes > 0 ? ListeningTime.label(minutes: minutes) : ""
        return [article.sourceLabel, (hearing ? nil : listen.label.detail) ?? total].filter { !$0.isEmpty }
    }

    /// The sentence at the page's saved listening spot, while it is part-way through: the text
    /// opens with it in the middle, underlined, where Continue starts.
    private func savedSentence(_ start: ListenSpot) -> ReaderSentence? {
        guard start.isPartWay else { return nil }
        return ReaderSentence(in: article.document, paragraph: start.paragraph, utf16Offset: start.utf16Offset)
    }

    /// *Play from Here* on a selection: from its sentence's start. The page you hear moves its
    /// playhead; another page starts, and Now Playing rises.
    private func playFromSelection(_ listen: QuickListen, hearing: Bool, paragraph: Int, offset: Int) {
        let document = hearing ? speech.document : article.document
        guard let spot = ListenSpot.fromSelection(in: document, paragraph: paragraph, offset: offset) else { return }
        guard hearing else {
            speech.listen(to: article, at: spot)
            shell.showNowPlaying()
            return
        }
        following = true
        speech.play(fromParagraph: spot.paragraph)
        if spot.utf16Offset > document.startUTF16Offset(forParagraph: spot.paragraph) {
            speech.seek(toUTF16Offset: spot.utf16Offset)
        }
    }

    /// The sentences of what is playing, for the underline.
    private func buildScrubMap(_ hearing: Bool) async {
        guard hearing else {
            scrubMap = nil
            return
        }
        let paragraphs = speech.document.paragraphs
        guard !paragraphs.isEmpty else { return }
        let map = await Task.detached(priority: .userInitiated) { ReaderScrubMap(paragraphs: paragraphs) }.value
        if !Task.isCancelled { scrubMap = map }
    }

    // MARK: - Edge swipe

    @ViewBuilder
    private var edgeSwipe: some View {
        if let onEdgeSwipeBack {
            Color.clear
                .frame(width: Spacing.m)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Spacing.xs).onEnded { drag in
                    if drag.translation.width > Self.backSwipeDistance { onEdgeSwipeBack() }
                })
                .accessibilityHidden(true)
        }
    }

    /// How far a swipe from the edge travels before it counts as going back.
    private static let backSwipeDistance: CGFloat = 60

    private struct WarmKey: Hashable {
        let id: UUID
        let count: Int
    }

    private struct ScrubKey: Hashable {
        let hearing: Bool
        let count: Int
    }
}
