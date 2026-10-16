import SwiftData
import SwiftUI
import UIKit

/// The Now Playing bar in the Reader sheet: what you hear (`SpeechController.nowPlaying`), drawn
/// by the design system's `NowPlayingBar`. It hides before anything has played and after Stop
/// Listening, on Now Playing, and under other sheets.
///
/// Tap or swipe up opens Now Playing; long-press offers Stop Listening (decision D3). At the end of
/// a page it stays, with ▶ and "✓ Finished".
struct NowPlayingBarView: View {
    @Bindable var speech: SpeechController

    @Environment(ShellState.self) private var shell

    var body: some View {
        if let now = speech.nowPlaying, !shell.isNowPlayingPresented, shell.sheet == nil {
            BarProgress(speech: speech, now: now, spansSlots: BottomToolbarLayout.slotCount)
                .transition(.opacity)
        }
    }
}

/// The Now Playing bar in the band the browser and the Library share (`SurfaceBand`), across
/// toolbar slots 2–5. It is always there, at one height, so the band never changes size:
///
/// - what you hear, as in the Reader (`speech.nowPlaying`);
/// - nothing bound (before anything plays this launch, after Stop Listening): the page played
///   last, paused, with ▶ to resume it from its place and a tap to open it;
/// - nothing ever played: the greyed placeholder, "Nothing playing".
///
/// Under the Reader sheet (which shows its own bar), Now Playing and other sheets it keeps its
/// space but shows nothing, so there is only ever one bar.
struct BandNowPlayingBar: View {
    @Bindable var speech: SpeechController
    /// The surface is under the Reader sheet.
    var isCovered = false

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Query(LibraryQueries.lastPlayed) private var lastPlayed: [Page]

    private static let slots = BottomBandTopRow.barSlots

    private var isHidden: Bool {
        isCovered || shell.isNowPlayingPresented || shell.sheet != nil
    }

    var body: some View {
        Group {
            if isHidden {
                NowPlayingBar.placeholder(spansSlots: Self.slots)
                    .hidden()
                    .accessibilityHidden(true)
            } else if let now = speech.nowPlaying {
                BarProgress(speech: speech, now: now, spansSlots: Self.slots)
            } else if let page = lastPlayed.first(where: \.isLive) {
                ResumeBar(page: page, actions: LibraryActions(library: library, speech: speech, shell: shell))
            } else {
                NowPlayingBar.placeholder(spansSlots: Self.slots)
            }
        }
        .transition(.opacity)
    }
}

/// The bar itself. Its own view because it reads the live offset (progress, time left), which
/// moves several times a second while playing: only the bar redraws for it.
private struct BarProgress: View {
    let speech: SpeechController
    let now: NowPlaying
    let spansSlots: Int

    @Environment(ShellState.self) private var shell

    var body: some View {
        let doc = speech.document
        let offset = now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: offset, rate: speech.rateMultiplier)
        NowPlayingBar(
            title: now.title,
            detail: now.isFinished ? [ListeningTime.finishedLabel] : [now.source, ListeningTime.leftLabel(minutes: left)],
            artwork: now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
            artworkLetter: now.source.isEmpty ? now.title : now.source,
            progress: doc.progress(atUTF16Offset: offset),
            state: speech.playState(of: .page(now.pageKey)),
            spansSlots: spansSlots,
            onOpen: shell.showNowPlaying,
            onPlayPause: speech.pressNowPlaying,
            onStop: speech.stop
        )
    }
}

/// The page played last, while nothing is bound: ▶ plays it from its place (the row's ▶,
/// `LibraryActions.play`), a tap opens it (`LibraryActions.open`). Its state still comes from the
/// session, so ▶ turns into a spinner while it starts.
private struct ResumeBar: View {
    let page: Page
    let actions: LibraryActions

    var body: some View {
        // A delete being saved can redraw this once more after the page's data is gone; reading
        // it then traps (`isLive`), so the placeholder stands in.
        if page.isLive {
            bar
        } else {
            NowPlayingBar.placeholder(spansSlots: BottomBandTopRow.barSlots)
        }
    }

    @ViewBuilder private var bar: some View {
        let progress = PageProgress.of(page)
        NowPlayingBar(
            title: page.title,
            detail: detail(progress),
            artwork: page.artworkData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
            artworkLetter: source.isEmpty ? page.title : source,
            progress: fraction(progress),
            state: actions.playState(of: page),
            spansSlots: BottomBandTopRow.barSlots,
            identifier: "nowPlayingBarResume",
            onOpen: { actions.open(page) },
            onPlayPause: { actions.play(page) },
            onStop: nil
        )
    }

    /// The book or series it belongs to, else its site.
    private var source: String {
        if let folder = page.folder, folder.kind.isBookOrSeries { return folder.displayName }
        return page.byline
    }

    private func detail(_ progress: ListRow.Progress) -> [String] {
        switch progress {
        case .partWay(_, let minutesLeft): [source, ListeningTime.leftLabel(minutes: minutesLeft)]
        case .finished: [ListeningTime.finishedLabel]
        default: [source]
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
