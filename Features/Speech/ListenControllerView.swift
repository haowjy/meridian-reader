import SwiftUI

/// Now Playing's transport row: speed · prev · play · next · [trailing], in the five-slot grid
/// (`NowPlayingTransport`). It always acts on the session, which is what Now Playing shows.
/// `trailing` is Now Playing's ⋯ (bottom-right, the same spot as the browser's ⋯). A sideways
/// swipe on the row skips a paragraph; with developer options on, a long-press on play / pause
/// opens Listen debug.
struct ListenControllerView: View {
    var trailing: AnyView? = nil

    @Bindable var speech: SpeechController
    @State private var showSpeedPopover = false
    @State private var showListenDebug = false

    private var state: PlayState {
        speech.activeSessionID.map { speech.playState(of: .page($0)) } ?? .idle
    }

    var body: some View {
        NowPlayingTransport(
            state: state,
            rateLabel: speech.rateDisplayLabel,
            canSkipBack: speech.canSkipToPreviousParagraph,
            canSkipForward: speech.canSkipToNextParagraph,
            onRate: { showSpeedPopover = true },
            onSkipBack: speech.skipToPreviousParagraph,
            onSkipForward: speech.skipToNextParagraph,
            onPlayPause: {
                guard let id = speech.activeSessionID else { return }
                speech.press(.page(id)) {}
            },
            onPlayLongPress: speech.developerOptionsEnabled ? {
                showListenDebug = true
                speech.showListenDebug = true
            } : nil
        ) {
            if let trailing {
                trailing
            } else {
                Color.clear.frame(height: BottomChrome.rowHeight)
            }
        }
        // The popover points at the speed label in slot 1.
        .popover(isPresented: $showSpeedPopover, attachmentAnchor: .point(UnitPoint(x: 0.1, y: 0)),
                 arrowEdge: .bottom) {
            SpeedPickerPopover(speech: speech) {
                showSpeedPopover = false
            }
            .presentationCompactAdaptation(.popover)
        }
        .simultaneousGesture(paragraphSwipe)
        .sheet(isPresented: $showListenDebug) {
            ListenDebugPanel(speech: speech)
        }
        .onChange(of: speech.showListenDebug) { _, open in
            showListenDebug = open
        }
        .onChange(of: showListenDebug) { _, open in
            speech.showListenDebug = open
        }
        .onChange(of: speech.listenDebugEnabled) { _, enabled in
            if !enabled { speech.showBakeDebugOverlay = false }
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
                    if speech.canSkipToPreviousParagraph { speech.skipToPreviousParagraph() }
                case .left:
                    if speech.canSkipToNextParagraph { speech.skipToNextParagraph() }
                }
            }
    }
}

private struct SpeedPickerPopover: View {
    @Bindable var speech: SpeechController
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Speed")
                .typeStyle(.row, weight: .semibold)
                .padding(.horizontal, Spacing.xxs)

            VStack(spacing: 0) {
                ForEach(SpeechController.rateOptions, id: \.self) { rate in
                    Button {
                        speech.setRateMultiplier(rate)
                        onDone()
                    } label: {
                        HStack {
                            Text(label(for: rate))
                                .typeStyle(.row)
                                .monospacedDigit()
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if abs(speech.rateMultiplier - rate) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("listenSpeedOption-\(label(for: rate))")
                    if rate != SpeechController.rateOptions.last {
                        Divider()
                    }
                }
            }
            .background(Palette.chrome, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .padding(Spacing.m)
        .frame(minWidth: 220)
    }

    private func label(for rate: Double) -> String {
        abs(rate - 1.0) < 0.01 ? "1×" : String(format: "%g×", rate)
    }
}
