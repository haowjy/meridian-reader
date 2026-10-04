import SwiftUI

/// Single-row listen bar: speed · prev · play · next · [trailing].
/// Position (and "N of M") lives in the scrub row above it; Jump sits next to the scrubber.
/// `trailing` is the reader's ⋯ menu (bottom-right, the same spot as the browser's ⋯); voice
/// settings live in that menu, so the bar has no gear of its own.
/// Transparent and margin-free: `ArticleListenSurface` puts it in the shared bottom band.
struct ListenControllerView: View {
    let session: SpeechSession
    var resumeParagraph: Int = 0
    /// Document offset of the sentence Play starts at (scrubbed / stored), when not loaded.
    var resumeUTF16Offset: Int? = nil
    var onProgress: ((Int, Int) -> Void)? = nil
    var trailing: AnyView? = nil

    @Bindable var speech: SpeechController
    @State private var showSpeedPopover = false
    @State private var showListenDebug = false

    private var isThisSession: Bool {
        speech.activeSessionID == session.id
    }

    /// False while OfflineArticleView is still building paragraphs off the main thread.
    private var sessionReady: Bool {
        !session.document.isEmpty
    }

    var body: some View {
        // Debug chip, bake overlay, buffering / language notes live ABOVE the scrubber
        // (`ArticleListenSurface.listenStatusNotes`) so they never sit on ⋯ or push it.
        VStack(spacing: BottomChrome.rowSpacing) {
            // The browser's five-slot grid: `[1×][⏮][▶︎][⏭][⋯]` under `[‹][›][Search][ ][⋯]`,
            // plain 19 pt glyphs.
            BottomToolbarLayout {
                speedButton

                Button {
                    prepareIfNeeded()
                    speech.skipToPreviousParagraph()
                    reportProgress()
                } label: {
                    Image(systemName: "backward.end.fill").toolbarIconFrame()
                }
                .disabled(!sessionReady || (isThisSession && !speech.canSkipToPreviousParagraph))
                .accessibilityLabel("Previous paragraph")

                Button {
                    guard sessionReady else { return }
                    speech.toggle(session, resumeParagraph: resumeParagraph, resumeUTF16Offset: resumeUTF16Offset)
                    reportProgress()
                } label: {
                    Image(systemName: speech.showsPauseIcon(for: session.id) ? "pause.fill" : "play.fill")
                        .toolbarIconFrame()
                }
                .disabled(!sessionReady)
                .accessibilityIdentifier("listenPlayPause")
                .accessibilityLabel(speech.showsPauseIcon(for: session.id) ? "Pause" : "Play")
                .modifier(DebugLongPress(enabled: speech.developerOptionsEnabled) {
                    // Developer options: long-press play/pause opens Listen debug (also in Settings).
                    showListenDebug = true
                    speech.showListenDebug = true
                })

                Button {
                    prepareIfNeeded()
                    speech.skipToNextParagraph()
                    reportProgress()
                } label: {
                    Image(systemName: "forward.end.fill").toolbarIconFrame()
                }
                .disabled(!sessionReady || (isThisSession && !speech.canSkipToNextParagraph))
                .accessibilityLabel("Next paragraph")

                Group {
                    if let trailing {
                        trailing
                    } else {
                        Color.clear.frame(height: BottomChrome.rowHeight)
                    }
                }
            }
            // Tint, not foregroundStyle: a foreground style overrides the dimming SwiftUI gives
            // disabled buttons, so ⏮ / ⏭ at the first / last paragraph would look tappable.
            .tint(Palette.ink)
        }
        // No background or margins of its own: the reader puts it (under the scrub capsule) in
        // the shared bottom band (`bottomChromeBand`), exactly like the browser's toolbar row.
        .simultaneousGesture(paragraphSwipe)
        .background {
            if let onProgress {
                ListenProgressReporter(speech: speech, sessionID: session.id, onProgress: onProgress)
            }
        }
        .sheet(isPresented: $showListenDebug) {
            ListenDebugPanel(speech: speech)
        }
        .onChange(of: speech.showListenDebug) { _, open in
            if open { showListenDebug = true }
            else { showListenDebug = false }
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
                guard sessionReady,
                      let direction = SwipeGesturePolicy.horizontalDirection(
                        translation: value.translation,
                        predicted: value.predictedEndTranslation
                      )
                else { return }
                switch direction {
                case .right:
                    guard canSwipeToPreviousParagraph else { return }
                    prepareIfNeeded()
                    speech.skipToPreviousParagraph()
                case .left:
                    guard canSwipeToNextParagraph else { return }
                    prepareIfNeeded()
                    speech.skipToNextParagraph()
                }
                reportProgress()
            }
    }

    private var canSwipeToPreviousParagraph: Bool {
        isThisSession ? speech.canSkipToPreviousParagraph : resumeParagraph > 0
    }

    private var canSwipeToNextParagraph: Bool {
        isThisSession ? speech.canSkipToNextParagraph : resumeParagraph + 1 < session.document.count
    }

    private var speedButton: some View {
        Button {
            showSpeedPopover = true
        } label: {
            Text(speech.rateDisplayLabel)
                .toolbarTextFrame()
        }
        .accessibilityIdentifier("listenSpeed")
        .accessibilityLabel("Speed \(speech.rateDisplayLabel)")
        .popover(isPresented: $showSpeedPopover, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            SpeedPickerPopover(speech: speech) {
                showSpeedPopover = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func prepareIfNeeded() {
        speech.prepare(session, startingParagraph: resumeParagraph)
    }

    private func reportProgress() {
        guard speech.activeSessionID == session.id else { return }
        onProgress?(speech.currentParagraphIndex, speech.spokenUTF16Offset)
    }
}

/// Reports the live position of `sessionID` to `onProgress` when it is worth saving: a new
/// paragraph, playback stopping, or the app leaving the foreground. Not on every tick (the
/// offset moves several times a second while playing); the reader also saves when it closes,
/// and seeks / skips report right away. An empty view of its own, so it doesn't redraw anything.
private struct ListenProgressReporter: View {
    let speech: SpeechController
    let sessionID: UUID
    let onProgress: (Int, Int) -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: speech.currentParagraphIndex) { report() }
            .onChange(of: speech.isPlaying) { _, playing in
                if !playing { report() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { report() }
            }
    }

    private func report() {
        guard speech.activeSessionID == sessionID else { return }
        onProgress(speech.currentParagraphIndex, speech.spokenUTF16Offset)
    }
}

/// Long-press → action, attached only while `enabled` (a disabled long-press must not eat taps).
private struct DebugLongPress: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onLongPressGesture(minimumDuration: 0.6, perform: action)
        } else {
            content
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
