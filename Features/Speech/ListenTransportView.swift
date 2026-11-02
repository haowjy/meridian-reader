import SwiftUI

/// Now Playing's transport (`NowPlayingTransport`), acting on the session, which is what Now
/// Playing shows. On regular width the five-slot row, `[leading] [⏮] (⏸) [⏭] [trailing]`: 🔖 and
/// ⋯ in the Reader's slots. The compact player card takes the `card` size: ⏮ ▶ ⏭ alone, larger,
/// with no slots. A sideways swipe on it skips a paragraph; with developer options on, a
/// long-press on play / pause opens Listen debug.
struct ListenTransportView: View {
    var size = TransportSize.row
    var leading: AnyView? = nil
    var trailing: AnyView? = nil

    @Bindable var speech: SpeechController
    @Environment(ShellState.self) private var shell
    @Environment(DeveloperSettings.self) private var developer

    private var state: PlayState {
        speech.activeSessionID.map { speech.playState(of: .article($0)) } ?? .idle
    }

    var body: some View {
        NowPlayingTransport(
            state: state,
            size: size,
            canSkipBack: speech.canSkipToPreviousParagraph,
            canSkipForward: speech.canSkipToNextParagraph,
            onSkipBack: speech.skipToPreviousParagraph,
            onSkipForward: speech.skipToNextParagraph,
            onPlayPause: speech.pressNowPlaying,
            onPlayLongPress: developer.isEnabled ? { shell.present(.listenDebug) } : nil
        ) {
            slot(leading)
        } more: {
            slot(trailing)
        }
        .simultaneousGesture(paragraphSwipe)
    }

    @ViewBuilder
    private func slot(_ view: AnyView?) -> some View {
        if let view {
            view
        } else {
            Color.clear.frame(height: Control.tap)
        }
    }

    private var paragraphSwipe: some Gesture {
        DragGesture(minimumDistance: SwipeGesturePolicy.horizontalMinimumDistance)
            .onEnded { value in
                guard let direction = SwipeGesturePolicy.horizontalDirection(
                        translation: value.translation,
                        predicted: value.predictedEndTranslation
                      )
                else { return }
                switch direction {
                case .right:
                    speech.skipToPreviousParagraph()
                case .left:
                    speech.skipToNextParagraph()
                }
            }
    }
}

/// The playback speed ("1×", "1.25×"): at the trailing end of the regular-width scrub capsule, and
/// at the trailing end of the compact player card. A tap opens a system menu of the speeds, the
/// current one checked, the same setting as Settings › Listening › Speed.
struct SpeedButton: View {
    @Bindable var speech: SpeechController
    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        Menu {
            Picker(Verbs.speed, selection: Binding(get: { speech.rateMultiplier }, set: speech.setRateMultiplier)) {
                ForEach(ListenRate.options, id: \.self) { rate in
                    Text(ListenRate.label(rate)).tag(rate)
                        .accessibilityIdentifier("listenSpeedOption-\(ListenRate.label(rate))")
                }
            }
        } label: {
            Text(ListenRate.label(speech.rateMultiplier))
                .foregroundStyle(palette.ink)
                .fieldTextFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Verbs.speed) \(ListenRate.label(speech.rateMultiplier))")
        .accessibilityIdentifier("listenSpeed")
    }
}
