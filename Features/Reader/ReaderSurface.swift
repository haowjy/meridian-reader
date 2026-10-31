import SwiftUI

/// The Library's Read and the Browser's reader mode on compact width: an article's text in place
/// of the page under the bottom chrome, through the same reading page as the Reader and Now
/// Playing (`ReadingPage`, in place). So the text reads as the Appearance setting says (Pages or
/// Scroll), with the footer, a tap in the middle for full screen (the text alone, down to the
/// screen's foot: nothing floats over it), and *Play from Here* on a selection; the text opens at
/// the page's saved listening spot, underlined.
///
/// The title, then "site  length", are the first thing in the text and scroll with it. "▶ Listen",
/// a thin accent pill (an `OverTextPill`, Jump to Audio's twin), floats centred just above the
/// chrome, riding it as it folds, in Scroll and Pages, until this page is what you hear (then the
/// chrome's round Listen opens it); not in full screen. It plays the page from its saved spot
/// (`QuickListen`) and slides Listen up over this surface, which stays mounted under it: closing
/// Listen shows it again where it was. What is around the text is the chrome's (the field with Aa,
/// ‹). It is a plain reader whatever plays: the playhead (the spoken paragraph, its underlined
/// sentence, the text following the audio, Jump to Audio) is Listen's alone. Links navigate the
/// browser.
struct ReaderSurface: View {
    let article: ReaderArticle
    let speech: SpeechController
    /// Another layer is over it (the Library, Now Playing, a sheet): it stays mounted for its place
    /// in the text, but leaves the status bar and the chrome's fold to what shows.
    let covered: Bool
    /// The left-edge swipe: what the chrome's ‹ does (the web view's own swipe sits under this
    /// view, out of reach). nil when there is nothing to go back to.
    let onEdgeSwipeBack: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(\.readingAppearance) private var appearance

    @State private var chrome = ReadingChrome()

    private var palette: ReadingPalette { appearance.palette(accent: AppAppearance.shared.accent) }

    var body: some View {
        let listen = QuickListen(article: article, speech: speech, shell: shell, library: library)
        let hearing = listen.isHearing
        let place = inPlace
        ReadingPage(showing: .inPlace(place), chrome: chrome, palette: palette) {
            EmptyView()
        } banner: {
            EmptyView()
        } text: {
            text(listen, hearing: hearing)
        } band: {
            EmptyView()
        } floating: {
            EmptyView()
        } overText: {
            OverTextPill(label: Verbs.listen, symbol: Icons.play, shows: !hearing && !listen.isDisabled && !chrome.hidden,
                         identifier: "inPlaceListen", holdsPagesRoom: true, action: listen.press)
        }
        .overlay(alignment: .leading) { edgeSwipe }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inPlaceReader")
        .task(id: WarmKey(id: article.id, count: article.document.count)) { listen.warmUp() }
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

    /// The page's text; while it is what you hear, without the saved spot's underline (the spot moves as it plays).
    private func text(_ listen: QuickListen, hearing: Bool) -> some View {
        HTMLReadingView(
            html: article.readingHTML,
            heading: ReaderHeading(title: article.title, detail: detail(listen), besideMenu: true),
            activeParagraphIndex: nil, sentence: hearing ? nil : savedSentence(listen.start), opensAtSentence: !hearing,
            onOpenLink: { shell.navigate(to: $0) },
            pageTimeLeft: { [document = article.document, rate = speech.rateMultiplier] in
                ListeningTime.leftLabel(in: document, paragraph: $0, offset: $1, rate: rate, chapter: false)
            },
            onPlaySelection: { playFromSelection(listen, hearing: hearing, paragraph: $0, offset: $1) },
            onTapParagraph: { _ in })
    }

    /// The source, then the length before a start ("9 min") or the time left part-way ("6 min left"), as a row's second line says.
    private func detail(_ listen: QuickListen) -> [String] {
        let length = article.document.isEmpty ? article.plainText.utf16.count : article.document.utf16Length
        let minutes = ListeningTime.minutes(utf16Length: length, rate: speech.rateMultiplier)
        let total = minutes > 0 ? ListeningTime.label(minutes: minutes) : ""
        return [article.sourceLabel, listen.lengthDetail ?? total].filter { !$0.isEmpty }
    }

    /// The sentence at the page's saved listening spot, while it is part-way through: the text
    /// opens with it in the middle, underlined, where Continue starts.
    private func savedSentence(_ start: ListenSpot) -> ReaderSentence? {
        guard start.isPartWay else { return nil }
        return ReaderSentence(in: article.document, paragraph: start.paragraph, utf16Offset: start.utf16Offset)
    }

    /// *Play from Here* on a selection: from its sentence's start (the page you hear moves its
    /// playhead; another page starts), and Listen slides up, where the playhead shows.
    private func playFromSelection(_ listen: QuickListen, hearing: Bool, paragraph: Int, offset: Int) {
        let document = hearing ? speech.document : article.document
        guard let spot = ListenSpot.fromSelection(in: document, paragraph: paragraph, offset: offset) else { return }
        if hearing {
            speech.play(fromParagraph: spot.paragraph)
            if spot.utf16Offset > document.startUTF16Offset(forParagraph: spot.paragraph) {
                speech.seek(toUTF16Offset: spot.utf16Offset)
            }
        } else {
            speech.listen(to: article, at: spot)
        }
        shell.showNowPlaying()
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
}
