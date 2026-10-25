import SwiftData
import SwiftUI

/// What the chrome's ▶ stands for: what is bound to playback, else the page played last (resumed by
/// the button and by the pill's Reader segment). A `DynamicProperty`, so the host re-reads it when
/// playback or the Library changes without owning the query.
@MainActor
struct ChromePlayback: DynamicProperty {
    @Environment(\.speechController) private var speech
    @Environment(LibraryStore.self) private var library
    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Query(LibraryQueries.lastPlayed) private var lastPlayed: [Article]

    /// The page played last, while nothing is bound.
    private var resume: Article? { speech.nowPlaying == nil ? lastPlayed.first(where: \.isLive) : nil }
    private var actions: LibraryActions { LibraryActions(library: library, speech: speech, shell: shell, follow: follow) }

    /// There is something for ▶ to pause or resume, and for the Reader segment to open.
    var isAvailable: Bool { speech.nowPlaying != nil || resume != nil }

    /// ▶ / ⏸ beside the pill: pause or resume what is bound, or resume the page played last.
    var button: ChromePlayButton? {
        if let now = speech.nowPlaying {
            return ChromePlayButton(state: speech.playState(of: .article(now.articleKey)), progress: {
                let doc = speech.document
                return doc.progress(atUTF16Offset: now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset)
            }, action: speech.pressNowPlaying)
        }
        guard let article = resume else { return nil }
        let actions = actions
        return ChromePlayButton(state: actions.playState(of: article), progress: {
            switch actions.progress(of: article) {
            case .partWay(let fraction, _): fraction
            case .finished: 1
            default: 0
            }
        }, action: { actions.play(article) })
    }

    func select(_ target: ChromeDestination) {
        let actions = actions
        shell.select(target, isPlaying: speech.nowPlaying != nil, resume: resume.map { article in { actions.open(article) } })
    }
}
