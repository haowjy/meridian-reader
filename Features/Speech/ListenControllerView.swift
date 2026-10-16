import SwiftUI

/// Now Playing's transport row: [leading] [⏮] (⏸) [⏭] [trailing], in the five-slot
/// grid (`NowPlayingTransport`). It always acts on the session, which is what Now Playing shows.
/// `leading` is Now Playing's 🔖 and `trailing` its ⋯, in the Reader's slots. A sideways swipe on
/// the row skips a paragraph; with developer options on, a long-press on play / pause opens
/// Listen debug.
struct ListenControllerView: View {
    var leading: AnyView? = nil
    var trailing: AnyView? = nil

    @Bindable var speech: SpeechController

    private var state: PlayState {
        speech.activeSessionID.map { speech.playState(of: .page($0)) } ?? .idle
    }

    var body: some View {
        NowPlayingTransport(
            state: state,
            canSkipBack: speech.canSkipToPreviousParagraph,
            canSkipForward: speech.canSkipToNextParagraph,
            onSkipBack: speech.skipToPreviousParagraph,
            onSkipForward: speech.skipToNextParagraph,
            onPlayPause: speech.pressNowPlaying,
            onPlayLongPress: speech.developerOptionsEnabled ? { speech.showListenDebug = true } : nil
        ) {
            slot(leading)
        } more: {
            slot(trailing)
        }
        .simultaneousGesture(paragraphSwipe)
        .onChange(of: speech.listenDebugEnabled) { _, enabled in
            if !enabled { speech.showBakeDebugOverlay = false }
        }
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
    @State private var showsPicker = false

    var body: some View {
        Button { showsPicker = true } label: {
            Text(ListenRate.label(speech.rateMultiplier))
                .foregroundStyle(Palette.playerInk)
                .fieldTextFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Speed \(ListenRate.label(speech.rateMultiplier))")
        .accessibilityIdentifier("listenSpeed")
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            SpeedPickerPopover(speech: speech) { showsPicker = false }
                .presentationCompactAdaptation(.popover)
                // Drawn on the player, as the sheet it points from.
                .presentationBackground(Palette.playerBackground)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// The speed list, on the player's palette: its rows on a `playerCard` card.
private struct SpeedPickerPopover: View {
    @Bindable var speech: SpeechController
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Speed")
                .typeStyle(.row, weight: .semibold)
                .foregroundStyle(Palette.playerInk)
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
                                .foregroundStyle(Palette.playerInk)
                            Spacer()
                            if speech.rateMultiplier == rate {
                                Image(systemName: Icons.checkmark)
                                    .foregroundStyle(Palette.playerAccent)
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
            .background(Palette.playerCard, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .padding(Spacing.m)
        .frame(minWidth: 220)
    }
}
