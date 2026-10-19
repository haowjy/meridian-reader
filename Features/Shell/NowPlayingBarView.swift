import SwiftData
import SwiftUI
import UIKit

/// The Now Playing bar in the Reader sheet: what you hear (`SpeechController.nowPlaying`), drawn
/// by the design system's `NowPlayingBar`. It hides while nothing is bound (before anything has
/// played, after Stop Listening, once the page you hear is removed or deleted), on Now Playing,
/// and under other sheets.
///
/// Tap or swipe up opens Now Playing; long-press offers Stop Listening (decision D3) and Remove from
/// Library, which stops it too. At the end of a page it stays, with ▶ and "✓ Finished".
struct NowPlayingBarView: View {
    @Bindable var speech: SpeechController

    @Environment(ShellState.self) private var shell

    var body: some View {
        if let now = speech.nowPlaying, !shell.isNowPlayingPresented, shell.sheet == nil {
            BarProgress(speech: speech, now: now)
                .transition(.opacity)
        }
    }
}

/// The Now Playing bar in the band the browser and the Library share (`SurfaceBand`), the full
/// width of its first row. It is always there, at one height, so the band never changes size:
///
/// - what you hear, as in the Reader (`speech.nowPlaying`);
/// - nothing bound (before anything plays this launch, after Stop Listening, or once the page you
///   heard is removed or deleted): the page played last that is still in the Library or played
///   without saving (`LibraryQueries.lastPlayed`), paused, with ▶ to resume it from its place and
///   a tap to open it;
/// - no such page (nothing played yet, or every page played since removed or deleted): the
///   greyed placeholder, "Nothing playing".
///
/// Under the Reader sheet (which shows its own bar), Now Playing and other sheets it keeps its
/// space but shows nothing, so there is only ever one bar.
struct BandNowPlayingBar: View {
    @Bindable var speech: SpeechController
    /// The surface is under the Reader sheet.
    var isCovered = false

    @Environment(ShellState.self) private var shell
    @Environment(FollowCenter.self) private var follow
    @Environment(LibraryStore.self) private var library
    @Query(LibraryQueries.lastPlayed) private var lastPlayed: [Page]

    private var isHidden: Bool {
        isCovered || shell.isNowPlayingPresented || shell.sheet != nil
    }

    var body: some View {
        Group {
            if isHidden {
                NowPlayingBar.placeholder()
                    .hidden()
                    .accessibilityHidden(true)
            } else if let now = speech.nowPlaying {
                BarProgress(speech: speech, now: now)
            } else if let page = lastPlayed.first(where: \.isLive) {
                ResumeBar(page: page, actions: LibraryActions(library: library, speech: speech, shell: shell, follow: follow))
            } else {
                NowPlayingBar.placeholder()
            }
        }
        .transition(.opacity)
    }
}

/// The bar itself. Its own view because it reads the live offset (progress, time left), which
/// moves several times a second while playing: only the bar redraws for it. Its page, queried
/// once by the session's key (not fetched on each redraw), offers Remove from Library while it is
/// in the Library.
private struct BarProgress: View {
    let speech: SpeechController
    let now: NowPlaying

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(FollowCenter.self) private var follow
    @Query private var pages: [Page]
    @State private var cover = BarCover()

    init(speech: SpeechController, now: NowPlaying) {
        self.speech = speech
        self.now = now
        _pages = Query(LibraryQueries.page(key: now.pageKey))
    }

    var body: some View {
        let doc = speech.document
        let offset = now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: offset, rate: speech.rateMultiplier)
        NowPlayingBar(
            title: now.lineOne,
            // Untitled, line one is already its source.
            detail: now.isFinished ? [.finished]
                : [now.title == nil ? nil : now.source, ListeningTime.leftLabel(minutes: left)].compactMap { $0 }
                    .map { DetailPart($0) },
            artwork: cover.image(for: now.pageKey, data: now.artwork),
            artworkLetter: now.artworkLetter,
            progress: doc.progress(atUTF16Offset: offset),
            state: speech.playState(of: .page(now.pageKey)),
            onOpen: shell.showNowPlaying,
            onPlayPause: speech.pressNowPlaying,
            onStop: speech.stop,
            onRemove: removal
        )
    }

    /// Remove from Library, for the page you hear while it is in the Library.
    private var removal: (() -> Void)? {
        guard let page = pages.first, page.isLive, page.isInLibrary else { return nil }
        let actions = LibraryActions(library: library, speech: speech, shell: shell, follow: follow)
        return { actions.remove([page]) }
    }
}

/// The page played last, while nothing is bound: ▶ plays it from its place (the row's ▶,
/// `LibraryActions.play`), a tap opens it (`LibraryActions.open`), and a page in the Library can be
/// removed from it (long-press). Its state still comes from the session, so ▶ turns into a
/// spinner while it starts.
private struct ResumeBar: View {
    let page: Page
    let actions: LibraryActions

    @State private var cover = BarCover()

    var body: some View {
        // A delete being saved can redraw this once more after the page's data is gone; reading
        // it then traps (`isLive`), so the placeholder stands in.
        if page.isLive {
            bar
        } else {
            NowPlayingBar.placeholder()
        }
    }

    @ViewBuilder private var bar: some View {
        let progress = actions.progress(of: page)
        NowPlayingBar(
            title: page.lineOne,
            detail: detail(progress),
            artwork: cover.image(for: page.listenKey, data: page.artworkData),
            artworkLetter: page.artworkLetter,
            progress: fraction(progress),
            state: actions.playState(of: page),
            identifier: "nowPlayingBarResume",
            onOpen: { actions.open(page) },
            onPlayPause: { actions.play(page) },
            onStop: nil,
            onRemove: page.isInLibrary ? { actions.remove([page]) } : nil
        )
    }

    /// Its source (untitled, line one is already that), then the time left or ✓ Finished.
    private func detail(_ progress: ListRow.Progress) -> [DetailPart] {
        let source = page.givenTitle == nil ? [] : [DetailPart(page.source)]
        switch progress {
        case .partWay(_, let minutesLeft): return source + [DetailPart(ListeningTime.leftLabel(minutes: minutesLeft))]
        case .finished: return [.finished]
        default: return source
        }
    }

    private func fraction(_ progress: ListRow.Progress) -> Double {
        switch progress {
        case .partWay(let fraction, _): fraction
        case .finished: 1
        default: 0
        }
    }
}

/// The bar's cover, decoded once per page: the bar redraws several times a second while playing,
/// and a fresh `UIImage` each pass would decode the picture again. Not observed: filling it
/// redraws nothing.
private final class BarCover {
    private var key: UUID?
    private var data: Data?
    private var image: Image?

    func image(for key: UUID, data: Data?) -> Image? {
        if key != self.key || data != self.data {
            self.key = key
            self.data = data
            image = data.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        }
        return image
    }
}
