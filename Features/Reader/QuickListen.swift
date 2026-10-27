import SwiftUI

/// What Listen does for the article an in-place reader shows (the Library's Read, the Browser's
/// reader mode): where it starts, what it is called, and what a tap does. Values read from the
/// speech controller, the shell and the library at the moment of use, so the control that shows it
/// stays current as playback changes.
@MainActor
struct QuickListen {
    let article: ReaderArticle
    let speech: SpeechController
    let shell: ShellState
    let library: LibraryStore

    /// The Library's page for the article (a web page not saved has none).
    var page: Article? { library.article(key: article.id, canonicalURL: article.origin.canonicalURL) }

    /// Where Listen starts: the page's saved spot, or its top once it is finished.
    var start: ListenSpot { page?.listenStart ?? ListenSpot(paragraph: article.resumeParagraph) }

    /// The page is what you hear: the control goes to Now Playing instead of starting it over.
    var isHearing: Bool { shell.isHearingArticle(of: article) }

    /// Nothing to read aloud yet.
    var isDisabled: Bool { article.document.isEmpty }

    /// "Listen" and "9 min", "Continue" and "6 min left", or "Listen Again"; the page you hear is
    /// "Now Playing".
    var label: (title: String, detail: String?) {
        if isHearing { return (String(localized: "Now Playing"), nil) }
        return article.listenLabel(from: start, finished: page?.finishedAt != nil, rate: speech.rateMultiplier)
    }

    /// Plays the page from `start` and raises Now Playing (the Listen destination); this reader is
    /// only a temporary view, so it ends there. The page you hear goes to Now Playing as it is.
    func press() {
        if !isHearing { speech.listen(to: article, at: start) }
        shell.showNowPlaying()
    }

    /// Warms the page's audio for its start, once per content (`ReaderSurface` runs it).
    func warmUp() {
        speech.warmUp(article, from: start, saved: page?.isSavedToLibrary == true)
    }
}

/// The Library's Read: Aa at the left and *▶ Listen · 9 min* beside it, one capsule in the field's
/// place on row 1, next to ‹. The capsule draws its own surface, as the search field does.
struct ReaderListenCapsule: View {
    let article: ReaderArticle

    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.readingPalette) private var reading

    var body: some View {
        let listen = QuickListen(article: article, speech: speech, shell: shell, library: library)
        let label = listen.label
        HStack(spacing: Spacing.xxs) {
            TextAppearanceControl(arrowEdge: .bottom)
            Button(action: listen.press) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Icons.play)
                        .font(BottomChrome.chromeGlyph)
                    Text(label.title)
                        .typeStyle(.row, weight: .semibold)
                    if let detail = label.detail {
                        Text(detail)
                            .typeStyle(.row)
                            .foregroundStyle(reading?.secondaryInk ?? Palette.secondaryInk)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(listen.isHearing ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PillButton<EmptyView>.accessibilityLabel(title: label.title, detail: label.detail))
            }
            .buttonStyle(.plain)
            .disabled(listen.isDisabled)
            .accessibilityIdentifier("readerListen")
        }
        .bottomChromeField(leading: Spacing.xxs, trailing: Spacing.xxs)
    }
}

/// The Browser's reader mode: a round control at the end of the address row that listens to the
/// page. Headphones, the Listen tab's glyph, so it never reads as the chrome's ▶ / ⏸ (what is
/// bound to playback); accent while this page is what you hear, when it goes to Now Playing.
struct ReaderListenButton: View {
    let article: ReaderArticle

    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(\.readingPalette) private var reading

    var body: some View {
        let listen = QuickListen(article: article, speech: speech, shell: shell, library: library)
        let label = listen.label
        Button(action: listen.press) {
            Image(systemName: Icons.listen)
                .font(BottomChrome.chromeGlyph)
                .foregroundStyle(listen.isHearing ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
                .chromeSurface(Circle(), fill: BottomChrome.fieldFill(reading))
                .chromeLargeContent(Verbs.listen, symbol: Icons.listen)
        }
        .buttonStyle(.plain)
        .disabled(listen.isDisabled)
        .accessibilityLabel(PillButton<EmptyView>.accessibilityLabel(title: label.title, detail: label.detail))
        .accessibilityHint(String(localized: "Reads this page aloud."))
        .accessibilityIdentifier("readerListen")
    }
}
