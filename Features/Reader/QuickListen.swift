import SwiftUI

/// What ▶ Listen does for the article an in-place reader shows (the Library's Read, the Browser's
/// reader mode): where it starts and what a tap does. Values read from the speech controller, the
/// shell and the library at the moment of use, so they stay current as playback changes.
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

    /// What the source line says of the page's length: "9 min" before a start, "6 min left" part-way,
    /// nil once finished or while it is what you hear.
    var lengthDetail: String? {
        isHearing ? nil : article.listenLabel(from: start, finished: page?.finishedAt != nil, rate: speech.rateMultiplier).detail
    }

    /// Plays the page from `start` and slides Listen up over the reader, which stays under it. The
    /// page you hear goes to Listen as it is.
    func press() {
        guard !isDisabled else { return }
        if !isHearing { speech.listen(to: article, at: start) }
        shell.showNowPlaying()
    }

    /// Warms the page's audio for its start, once per content (`ReaderSurface` runs it).
    func warmUp() {
        speech.warmUp(article, from: start, saved: page?.isSavedToLibrary == true)
    }
}
