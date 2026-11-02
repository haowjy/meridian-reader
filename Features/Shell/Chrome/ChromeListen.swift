import SwiftData
import SwiftUI

/// Listen, the round button that ends row 1 on every destination: the headphones, or the playing
/// bars while something plays. A tap slides Listen up over everything: what is bound to playback;
/// else the page played last, bound paused at its saved place (`SpeechController.prepare`, so
/// Listen shows it and ▶ resumes it); else Listen's empty screen, *Nothing Playing*. It reads playback in
/// its own body, so the bars moving redraw this button and not the chrome.
struct ChromeListenButton: View {
    @Environment(\.speechController) private var speech
    @Environment(ShellState.self) private var shell
    @Environment(\.readingPalette) private var reading
    @Query(LibraryQueries.lastPlayed) private var lastPlayed: [Article]

    var body: some View {
        let playing = speech.nowPlaying.map { speech.playState(of: .article($0.articleKey)) == .playing } == true
        Button(action: open) {
            ChromeCircleFace(label: Verbs.listen, symbol: Icons.listen) {
                if playing {
                    PlayingBars(animating: true)
                        .frame(height: Glyph.small)
                        .foregroundStyle(reading?.accent ?? Palette.accent)
                } else {
                    Image(systemName: Icons.listen)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Verbs.listen)
        .accessibilityValue(playing ? String(localized: "Playing") : "")
        .accessibilityIdentifier("chromeListen")
    }

    private func open() {
        Self.open(speech: speech, shell: shell, lastPlayed: lastPlayed.first(where: \.isLive))
    }

    /// The tap: Listen on what is bound, else on `lastPlayed` bound paused at its place, else on
    /// nothing (`NowPlayingScreen` draws *Nothing Playing*).
    static func open(speech: SpeechController, shell: ShellState, lastPlayed: Article?) {
        if speech.nowPlaying == nil, let article = lastPlayed, article.hasText,
           case let session = SpeechSession.article(article), !session.document.isEmpty {
            speech.prepare(session, at: article.listenStart)
        }
        shell.showNowPlaying()
    }
}
