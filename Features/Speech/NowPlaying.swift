import Foundation

/// Where the playing page lives, shown as "Playing from …": the folder it is in (a book, a series,
/// Favorites or a folder you made), which playback carries on through; a page in no folder plays
/// from its site.
enum PlayingFrom: Equatable {
    case folder(id: UUID, name: String)
    case site(host: String)

    /// "Pride and Prejudice", "Finance", "investopedia.com".
    var name: String {
        switch self {
        case .folder(_, let name): name
        case .site(let host): host
        }
    }
}

/// The hearing state as every surface shows it: the Now Playing bar, Now Playing, the lock screen.
/// Derived by `SpeechController` from the session and its metadata; views never assemble it.
struct NowPlaying: Equatable {
    var pageKey: UUID
    /// Web pages: what 🎧 compares against.
    var canonicalURL: String?
    var title: String
    /// The book or series for a chapter ("Pride and Prejudice"), else the site
    /// ("investopedia.com").
    var source: String
    var artwork: Data?
    var playingFrom: PlayingFrom
    /// `.prepared` and `.finished` included: the bar stays for both.
    var phase: PlaybackPhase

    var isFinished: Bool { phase == .finished }
}

/// What a play button is for.
enum ListenTarget: Equatable {
    /// A page by its key (the audio cache key).
    case page(UUID)
    /// A web page by its canonical URL. Canonical strings are compared directly, so a saved
    /// article with a pre-v2 random id still matches the page it came from.
    case webPage(canonicalURL: String)
    /// A folder (a book, a series, Favorites, a folder you made): what you hear while any of its
    /// pages plays.
    case folder(UUID)
}

/// One request to make `target` ready to play (🎧 while its page extracts). Compared by identity:
/// two taps on the same page are two requests, and only the newest may start.
struct ListenPreparation: Equatable {
    let id = UUID()
    let target: ListenTarget
}

/// Where Now Playing's text comes from. `SpeechSession` carries the paragraphs, not the reading
/// HTML, and some starts never had a `ReaderArticle` (a Saved row's ▶, crash resume), so the
/// content is resolved by key when Now Playing shows: the playing page in the library, which has
/// every page that has played (`ListeningProgressRecorder` keeps one played without saving).
/// Injected at the composition root, so the speech stack never touches the library store.
@MainActor
protocol NowPlayingContentResolving: AnyObject {
    /// The reading content for `pageKey`, or nil when it can't be found.
    func content(for pageKey: UUID) async -> ReaderArticle?
}

/// The library as playback through a folder sees it (`SpeechController+Advance`): a book's or
/// series' chapters, or the pages of any other folder. Injected at the composition root, so the
/// speech stack never touches SwiftData.
@MainActor
protocol NextChapterProviding: AnyObject {
    /// The folder `pageKey` is in (nil: a page in no folder).
    func folder(containing pageKey: UUID) -> PlaybackFolder?
    /// The folder's pages in play order, skipped ones included.
    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter]
    /// A chapter's listening session (paragraphs and what the lock screen shows).
    func load(_ pageKey: UUID) -> SpeechSession?
    /// Fetches a link chapter's text, so it can play; false when it couldn't be had.
    func fetch(_ pageKey: UUID) async -> Bool
    /// The chapter played to its end, playing `text` (`PlaybackSessionState.textFingerprint`), and
    /// playback carried on past it. Marked finished only while its page holds that text.
    func pageFinished(key: UUID, text: String?)
}

/// A folder playback carries on through.
struct PlaybackFolder: Equatable, Sendable {
    var id: UUID
    var name: String
    /// A book or series (`FolderKind.isBookOrSeries`): its pages are chapters, and the bar's
    /// source names it. Any other folder's pages show their site there.
    var isBookOrSeries: Bool
}

/// A position the playback session reached that is worth keeping: a new paragraph, a phase
/// change (pause, finish, stop), a page being replaced. Delivered to `ListeningProgressRecorder`.
struct ListenProgress: Equatable {
    var pageKey: UUID
    /// The text it was reached in (`PlaybackSessionState.textFingerprint`): it is stored only on a
    /// page holding that text.
    var text: String?
    var paragraph: Int
    var utf16Offset: Int
    var phase: PlaybackPhase
}
