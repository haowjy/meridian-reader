import Foundation

/// Where the playing page lives, shown as "Playing from …" and as the bar's source. A page in no
/// folder plays from its site.
enum PlayingFrom: Equatable {
    case site(host: String)

    /// "investopedia.com".
    var name: String {
        switch self {
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
    /// "investopedia.com".
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
    /// A book or series: what you hear while any of its chapters plays.
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

/// The library as playback through a book or series sees it (`SpeechController+Advance`).
/// Injected at the composition root, so the speech stack never touches SwiftData.
@MainActor
protocol NextChapterProviding: AnyObject {
    /// The book or series `pageKey` is a chapter of (nil: a page in no book or series).
    func folder(containing pageKey: UUID) -> PlaybackFolder?
    /// The chapters of a book or series in play order, skipped ones included (empty for any
    /// other folder).
    func chapters(of folderID: UUID) -> [ChapterAdvance.Chapter]
    /// A chapter's listening session (paragraphs and what the lock screen shows).
    func load(_ pageKey: UUID) -> SpeechSession?
    /// Fetches a link chapter's text, so it can play; false when it couldn't be had.
    func fetch(_ pageKey: UUID) async -> Bool
    /// The chapter played to its end and playback carried on past it.
    func pageFinished(key: UUID)
}

/// A book or series playback carries on through.
struct PlaybackFolder: Equatable {
    var id: UUID
    var name: String
}

/// A position the playback session reached that is worth keeping: a new paragraph, a phase
/// change (pause, finish, stop), a page being replaced. Delivered to `ListeningProgressRecorder`.
struct ListenProgress: Equatable {
    var pageKey: UUID
    var paragraph: Int
    var utf16Offset: Int
    var phase: PlaybackPhase
}
