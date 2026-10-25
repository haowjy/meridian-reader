import SwiftData
import SwiftUI
import UIKit

/// The Now Playing bar in the Reader sheet: what you hear (`SpeechController.nowPlaying`), drawn
/// by the design system's `NowPlayingBar`. It hides while nothing is bound (before anything has
/// played, after Stop Listening, once the page you hear is removed or deleted), on Now Playing,
/// and under other sheets.
///
/// Tap or swipe up opens Now Playing; long-press shows the page's menu (`ArticleMenu`), then Stop
/// Listening (decision D3). At the end of a page it stays, with ▶ and Finished.
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

/// The bar itself. Its own view because it reads the live offset (progress, time left), which
/// moves several times a second while playing: only the bar redraws for it. Its page, queried
/// once by the session's key (not fetched on each redraw), is what its menu acts on.
private struct BarProgress: View {
    let speech: SpeechController
    let now: NowPlaying

    @Environment(ShellState.self) private var shell
    @Environment(LibraryStore.self) private var library
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Query private var articles: [Article]
    @State private var cover = BarCover()

    init(speech: SpeechController, now: NowPlaying) {
        self.speech = speech
        self.now = now
        _articles = Query(LibraryQueries.article(key: now.articleKey))
    }

    var body: some View {
        let doc = speech.document
        let offset = now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: offset, rate: speech.rateMultiplier)
        NowPlayingBar(
            title: now.lineOne,
            detail: now.isFinished ? [.finished]
                // Line two names its folder when it is in one, as Recent's rows do (C130), else its source.
                : [articles.first?.folder?.name ?? ArticleRowTitle.lineTwoSource(title: now.title, source: now.source),
                   ListeningTime.leftLabel(minutes: left)]
                    .compactMap { $0 }.map { DetailPart($0) },
            artwork: cover.image(for: now.articleKey, data: now.artwork),
            artworkLetter: now.artworkLetter,
            progress: doc.progress(atUTF16Offset: offset),
            state: speech.playState(of: .article(now.articleKey)),
            onOpen: shell.showNowPlaying,
            onPlayPause: speech.pressNowPlaying,
            menu: AnyView(BarMenu(actions: ArticleActions(article: articles.first.flatMap { $0.isLive ? $0 : nil }, library: library,
                                                       shell: shell, speech: speech, preparedAudio: preparedAudio, follow: follow),
                                  onStop: speech.stop))
        )
    }
}

/// The bar's long press: the page's menu (`ArticleMenu`), then *Stop Listening* (dimmed with
/// nothing loaded). A view of its own, so the rows are built only when the menu shows, not on
/// each of the bar's redraws.
private struct BarMenu: View {
    let actions: ArticleActions
    let onStop: (() -> Void)?

    var body: some View {
        ArticleMenu(actions: actions, place: .bar(onStop: onStop))
    }
}

/// The bar's cover, decoded once per page: the bar redraws several times a second while playing,
/// and a fresh `UIImage` each pass would decode the picture again. Not observed: filling it
/// redraws nothing.
final class BarCover {
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
