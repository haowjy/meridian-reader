import SwiftUI

/// Now Playing's transport row: [leading] [⏮] (⏸) [⏭] [trailing], in the five-slot
/// grid (`NowPlayingTransport`). It always acts on the session, which is what Now Playing shows.
/// `leading` is Now Playing's 🔖 and `trailing` its ⋯, in the Reader's slots. A sideways swipe on
/// the row skips a paragraph; with developer options on, a long-press on play / pause opens
/// Listen debug.
struct ListenTransportView: View {
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
            Color.clear.frame(height: BottomChrome.rowHeight)
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

/// The playback speed ("1×", "1.25×") at the trailing end of Now Playing's scrub capsule; a tap
/// opens the speed list, pointing at it.
struct SpeedButton: View {
    @Bindable var speech: SpeechController
    /// On the round control face of the player card's transport (as Aa across from it), not bare
    /// text in a scrub capsule.
    var round = false
    @State private var showsPicker = false
    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        Button { showsPicker = true } label: {
            if round {
                Text(ListenRate.label(speech.rateMultiplier))
                    .foregroundStyle(palette.ink)
                    .roundFieldText(fill: BottomChrome.fieldFill(reading))
            } else {
                Text(ListenRate.label(speech.rateMultiplier))
                    .foregroundStyle(palette.ink)
                    .fieldTextFrame()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Verbs.speed) \(ListenRate.label(speech.rateMultiplier))")
        .accessibilityIdentifier("listenSpeed")
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            SpeedPickerPopover(speech: speech) { showsPicker = false }
                .presentationCompactAdaptation(.popover)
                // In the reading theme, as the sheet it points from.
                .presentationBackground(palette.background)
                .readingSurface(palette)
        }
    }
}

/// The speed list, in the reading theme: its rows on a card.
private struct SpeedPickerPopover: View {
    @Bindable var speech: SpeechController
    var onDone: () -> Void

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(Verbs.speed)
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, Spacing.xxs)

            VStack(spacing: 0) {
                ForEach(ListenRate.options, id: \.self) { rate in
                    Button {
                        speech.setRateMultiplier(rate)
                        onDone()
                    } label: {
                        HStack {
                            Text(ListenRate.label(rate))
                                .typeStyle(.row)
                                .monospacedDigit()
                                .foregroundStyle(palette.ink)
                            Spacer()
                            if speech.rateMultiplier == rate {
                                Image(systemName: Icons.checkmark)
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("listenSpeedOption-\(ListenRate.label(rate))")
                    if rate != ListenRate.options.last {
                        Divider()
                    }
                }
            }
            .background(palette.card, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .padding(Spacing.m)
        .frame(minWidth: 220)
    }
}
