import SwiftUI
import UIKit

/// The Now Playing bar on a surface: what you hear (`SpeechController.nowPlaying`), drawn by the
/// design system's `NowPlayingBar`. The same on the browser, the start page, the Library and the
/// Reader sheet. It hides before anything has played and after Stop Listening, on Now Playing,
/// and under other sheets; the surfaces hide it while you type.
///
/// Tap or swipe up opens Now Playing; long-press offers Stop Listening (decision D3). At the end of
/// a page it stays, with ▶ and "✓ Finished".
struct NowPlayingBarView: View {
    @Bindable var speech: SpeechController
    /// The surface showing it is under a sheet (the browser or the Library under a Reader): the
    /// sheet shows the bar instead, so there is only ever one.
    var isCovered = false

    @Environment(ShellState.self) private var shell

    var body: some View {
        if let now = speech.nowPlaying, !isCovered, !shell.isNowPlayingPresented, shell.sheet == nil {
            BarProgress(speech: speech, now: now, state: speech.playState(of: .page(now.pageKey)),
                        artwork: now.artwork.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                        onOpen: shell.showNowPlaying,
                        onPlayPause: { speech.press(.page(now.pageKey)) {} },
                        onStop: speech.stop)
                .transition(.opacity)
        }
    }
}

/// The bar itself. Its own view because it reads the live offset (progress, time left), which
/// moves several times a second while playing: only the bar redraws for it.
private struct BarProgress: View {
    let speech: SpeechController
    let now: NowPlaying
    let state: PlayState
    let artwork: Image?
    let onOpen: () -> Void
    let onPlayPause: () -> Void
    let onStop: () -> Void

    var body: some View {
        let doc = speech.document
        let offset = now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset
        let left = ListeningTime.minutesLeft(in: doc, fromUTF16Offset: offset, rate: speech.rateMultiplier)
        NowPlayingBar(
            title: now.title,
            detail: now.isFinished ? "✓ Finished" : [now.source, "\(left) min left"].filter { !$0.isEmpty }
                .joined(separator: " · "),
            artwork: artwork,
            artworkLetter: now.source.isEmpty ? now.title : now.source,
            progress: doc.progress(atUTF16Offset: offset),
            state: state,
            onOpen: onOpen,
            onPlayPause: onPlayPause,
            onStop: onStop
        )
    }
}
