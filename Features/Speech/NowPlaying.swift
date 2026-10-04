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
}

/// Where Now Playing's text comes from. `SpeechSession` carries the paragraphs, not the reading
/// HTML, and some starts never had a `ReaderArticle` (a Saved row's ▶, crash resume), so the
/// content is resolved by key when Now Playing shows. Injected at the composition root, so the
/// speech stack never touches the library store.
@MainActor
protocol NowPlayingContentResolving: AnyObject {
    /// A page started from a `ReaderArticle` (the Reader's Listen, 🎧): kept in memory, so an
    /// unsaved page can still be shown.
    func remember(_ article: ReaderArticle)
    /// The reading content for `pageKey`, or nil when it can't be found.
    func content(for pageKey: UUID) async -> ReaderArticle?
}

/// A position the playback session reached that is worth keeping: a new paragraph, a phase
/// change (pause, finish, stop), a page being replaced. Delivered to `ListeningProgressRecorder`.
struct ListenProgress: Equatable {
    var pageKey: UUID
    var paragraph: Int
    var utf16Offset: Int
    var phase: PlaybackPhase
}
