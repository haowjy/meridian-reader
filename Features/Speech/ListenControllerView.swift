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

    private var isSpeakingHere: Bool {
        speech.isActive(sessionID: session.id)
    }

    /// False while OfflineArticleView is still building paragraphs off the main thread.
    private var sessionReady: Bool {
        !session.document.isEmpty
    }

    var body: some View {
        // Debug chip, bake overlay, buffering / language notes live ABOVE the scrubber
        // (`ArticleListenSurface.listenStatusNotes`, Nav J) so they never sit on ⋯ or push it.
        VStack(spacing: 4) {
            // The browser's five-slot grid (Nav I): `[1×][⏮][▶︎][⏭][⋯]` under `[‹][›][Search][ ][⋯]`,
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
            .foregroundStyle(.primary)
        }
        // No background or margins of its own: the reader puts it (under the scrub capsule) in
        // the shared bottom band (`bottomChromeBand`), exactly like the browser's toolbar row.
        .simultaneousGesture(paragraphSwipe)
        .onChange(of: speech.currentParagraphIndex) { _, _ in reportProgress() }
        .onChange(of: speech.spokenUTF16Offset) { _, _ in reportProgress() }
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
                .font(.system(size: 17, weight: .medium).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: BottomChrome.rowHeight)
                .contentShape(Rectangle())
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Speed")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(SpeechController.rateOptions, id: \.self) { rate in
                    Button {
                        speech.setRateMultiplier(rate)
                        onDone()
                    } label: {
                        HStack {
                            Text(label(for: rate))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.primary)
                            Spacer()
                            if abs(speech.rateMultiplier - rate) < 0.01 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("listenSpeedOption-\(label(for: rate))")
                    if rate != SpeechController.rateOptions.last {
                        Divider()
                    }
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .frame(minWidth: 220)
    }

    private func label(for rate: Double) -> String {
        abs(rate - 1.0) < 0.01 ? "1×" : String(format: "%g×", rate)
    }
}
