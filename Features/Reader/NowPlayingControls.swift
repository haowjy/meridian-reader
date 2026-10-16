import SwiftUI

/// Now Playing's bottom band (in the reading theme's colours), top to bottom: the status notes (buffering, the Apple-fallback and
/// language notes, the developer Debug chip; "✓ Finished" is the title card's), the scrub row (sentence-precise
/// scrubber, the speed at its end) and the transport row (🔖 and ⋯ in the Reader's slots). Notes sit above the scrubber so appearing text
/// never pushes it when you skip.
///
/// Only the leaves that need the live offset read it (`PlayheadReader`), so playback ticks don't
/// redraw the band.
struct NowPlayingControls: View {
    @Bindable var speech: SpeechController
    @Environment(ShellState.self) private var shell
    let scrubMap: ReaderScrubMap?
    let detectedLanguage: String?
    /// 🔖, transport slot 1.
    let save: AnyView
    /// ⋯, transport slot 5.
    let more: AnyView
    /// Paragraph under the scrub thumb while dragging (nil when the drag ends).
    let onScrubPreview: (Int?) -> Void

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    /// The same fact the title card reads for its "✓ Finished".
    private var isFinished: Bool { speech.nowPlaying?.isFinished == true }

    var body: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            notes
            // The drag bubble spans the band's width.
            scrubRow
                .readerScrubBubble()
            ListenControllerView(leading: save, trailing: more, speech: speech)
        }
    }

    @ViewBuilder
    private var scrubRow: some View {
        if let scrubMap {
            let doc = speech.document
            let buffered = bufferedSpans(scrubMap)
            PlayheadReader(speech: speech) { spot in
                ReaderScrubRow(
                    map: scrubMap,
                    position: Self.scrubFraction(scrubMap, document: doc, spot: spot),
                    buffered: buffered,
                    onScrubPreview: onScrubPreview,
                    onScrubCommit: seek(to:)
                ) {
                    SpeedButton(speech: speech)
                }
            }
        } else {
            // Holds the capsule's place (and the speed) until the scrub map is built, so nothing
            // shifts.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SpeedButton(speech: speech)
            }
            .bottomChromeField()
        }
    }

    /// Buffering / Apple-fallback / language notes and the developer Debug chip.
    @ViewBuilder
    private var notes: some View {
        let languageNote = speech.languageResolution(detected: detectedLanguage).note
        if speech.showsListenDebugUI, speech.showBakeDebugOverlay {
            BakeDebugOverlay(speech: speech) {
                shell.present(.listenDebug)
            }
        }
        if speech.showsListenDebugUI {
            HStack {
                Spacer(minLength: 0)
                Button {
                    speech.showBakeDebugOverlay.toggle()
                } label: {
                    Text(speech.showBakeDebugOverlay ? "Debug ▾" : "Debug")
                        .typeStyle(.caption, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule().fill(speech.showBakeDebugOverlay ? palette.highlight : palette.card)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listenBakeDebugChip")
                .accessibilityLabel(speech.showBakeDebugOverlay ? "Hide bake debug" : "Show bake debug")
            }
            .padding(.horizontal, Spacing.xs)
        }
        if isFinished {
            // The title card says "✓ Finished"; no note under it.
            EmptyView()
        } else if speech.isBufferingNext {
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing next…")
                    .accessibilityIdentifier("listenBufferingLabel")
                Spacer(minLength: 0)
            }
            .typeStyle(.caption)
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, Spacing.xs)
            .accessibilityIdentifier("listenBuffering")
        } else if let renderNote = speech.renderNote {
            note(renderNote, id: "listenRenderNote")
        } else if let languageNote {
            note(languageNote, id: "listenLanguageNote")
        }
    }

    private func note(_ text: String, id: String) -> some View {
        Text(text)
            .typeStyle(.caption)
            .foregroundStyle(palette.secondaryInk)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .accessibilityIdentifier(id)
    }

    /// Scrubber fraction of `spot`. `ReaderScrubMap` keeps a spot inside its paragraph (< 1 of
    /// it), so the end of a paragraph never reads as the start of the next one.
    private static func scrubFraction(_ map: ReaderScrubMap, document doc: ParagraphDocument,
                                      spot: PlayheadSpot) -> Double {
        guard doc.paragraphs.indices.contains(spot.paragraph) else { return map.fraction(paragraph: spot.paragraph) }
        return map.fraction(paragraph: spot.paragraph, offset: spot.utf16Offset - doc.startUTF16Offset(forParagraph: spot.paragraph))
    }

    /// Lighter "buffered" fill (like a video player): stretches of rendered audio, as scrubber
    /// fractions. Local engine only (Apple speaks live, so there's nothing to show).
    private func bufferedSpans(_ map: ReaderScrubMap) -> [ClosedRange<Double>] {
        guard let id = speech.activeSessionID,
              let ready = speech.bakeReadyParagraphIndices(articleID: id, paragraphCount: speech.document.count,
                                                           detectedLanguage: detectedLanguage),
              !ready.isEmpty else { return [] }
        return map.spans(covering: ready)
    }

    /// Scrubber release: the playhead to the sentence under the thumb. Playing keeps playing from
    /// that sentence; paused stays paused there (a real seek, not stop-and-reload); finished just
    /// moves where ▶ starts.
    private func seek(to target: ReaderScrubMap.Target) {
        let doc = speech.document
        guard !doc.isEmpty else { return }
        speech.seek(toUTF16Offset: doc.startUTF16Offset(forParagraph: target.paragraph) + target.offset)
    }
}

/// A playhead position: paragraph + document UTF-16 offset inside it.
struct PlayheadSpot: Equatable {
    var paragraph: Int
    var utf16Offset: Int
}

/// Hands `content` the live playhead. The live offset moves several times a second while playing;
/// reading it here, in its own body, keeps those redraws to `content` instead of the view that
/// builds it.
struct PlayheadReader<Content: View>: View {
    let speech: SpeechController
    @ViewBuilder let content: (PlayheadSpot) -> Content

    var body: some View {
        content(PlayheadSpot(paragraph: speech.currentParagraphIndex, utf16Offset: speech.spokenUTF16Offset))
    }
}

/// A one-shot "scroll this paragraph into view" (token changes per request).
struct ReaderScrollRequest: Equatable {
    let index: Int
    let token: Int
}
