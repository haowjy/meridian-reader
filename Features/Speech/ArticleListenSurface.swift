import SwiftUI

/// Shared reading body + scrub row + listen bar used by `ArticleReaderScreen` (Browse Reader and
/// Saved alike). Uses `session.document` as the single paragraph source once speech is prepared.
/// Jump mode is owned by the screen and passed in as a binding.
///
/// Bottom, top to bottom: status notes (buffering / language), then
/// `[back] ( [scrubber][select paragraph][bookmark] )`, then the listen controls. `back` is the
/// reader's one close control (`ReaderBackButton`). Status notes sit above
/// the scrubber so skip / preparing text never pushes it.
///
/// Lay this out edge to edge (`ignoresSafeArea`) and pass the real safe area in `safeInsets`; the
/// text scrolls under the bars but is inset so its first / last lines always clear them.
/// The bottom chrome is the browser's own bottom band (`BottomChrome.swift`): the scrub row is a
/// field capsule like the address field, the listen controls a toolbar row like `[‹][›][⋯]`.
/// Like the browser's search bar it never hides.
///
/// This body follows the playhead per paragraph only (highlight, where Play starts). The offset
/// inside the paragraph moves several times a second while playing; only `PlayheadReader`
/// leaves (scrubber thumb, UI-test marker) read it, so playback ticks don't redraw the reader.
struct ArticleListenSurface: View {
    let cleanedHTML: String
    var pageTitle: String? = nil
    let session: SpeechSession
    var resumeParagraph: Int = 0
    /// Stored document offset for `resumeParagraph` (saved row); Play resumes at its sentence.
    var resumeUTF16Offset: Int? = nil
    var onProgress: ((Int, Int) -> Void)? = nil

    /// "Pick a paragraph" mode. Off by default so scrolling / reading taps never move playback.
    @Binding var jumpMode: Bool

    @Bindable var speech: SpeechController

    /// Save / Jump state + actions for the scrub row.
    let scrubControls: ReaderScrubControls
    /// The reader's ⋯ button, in the listen bar's rightmost slot.
    var listenTrailing: AnyView? = nil

    /// The screen's safe area (this view itself runs edge to edge).
    var safeInsets = EdgeInsets()
    /// Height of the screen's own floating top row below the safe area (0 when it lives in a
    /// navigation bar, which is already part of the safe area).
    var topChromeHeight: CGFloat = 0

    @State private var scrubMap: ReaderScrubMap?
    /// Paragraph under the scrubber thumb while dragging (highlighted + scrolled to).
    @State private var scrubPreview: Int?
    @State private var scrollRequest: ReaderScrollRequest?
    /// Scrubbed position for an article that isn't the loaded session (Play starts here).
    @State private var localResume: Int?
    /// Scrubbed sentence (document UTF-16 offset) for an article that isn't the loaded session.
    @State private var localResumeOffset: Int?
    /// Measured height of the bottom band (including the home-indicator area).
    @State private var bottomChromeHeight: CGFloat = 0

    private var isLoaded: Bool { speech.isPrepared(sessionID: session.id) }

    /// Where Play starts: the live playhead when loaded, else the scrubbed / stored position.
    private var effectiveResume: Int {
        isLoaded ? speech.currentParagraphIndex : (localResume ?? resumeParagraph)
    }

    /// Where Play starts inside `effectiveResume` (document offset of a sentence start), when not
    /// loaded: the scrubbed sentence, else the stored offset snapped to its sentence start.
    private var effectiveResumeOffset: Int? {
        guard !isLoaded else { return nil }
        let doc = readingDocument
        guard !doc.isEmpty else { return nil }
        let paragraph = effectiveResume
        let candidate = localResume != nil ? localResumeOffset : resumeUTF16Offset
        guard let offset = candidate, doc.index(containingUTF16Offset: offset) == paragraph else { return nil }
        let start = doc.startUTF16Offset(forParagraph: paragraph)
        guard let scrubMap else { return offset }
        return start + scrubMap.target(paragraph: paragraph, offset: offset - start).offset
    }

    /// Highlighted paragraph. The reader looks the same live or not: it shows where Play starts.
    private var activeIndex: Int { scrubPreview ?? effectiveResume }

    private var textInsets: ReaderTextInsets {
        ReaderTextInsets(top: safeInsets.top + topChromeHeight,
                         bottom: max(bottomChromeHeight, safeInsets.bottom) + 6)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            readingView

            bottomChrome
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    if abs($0 - bottomChromeHeight) > 0.5 { bottomChromeHeight = $0 }
                }
        }
        .task(id: ScrubMapKey(count: readingDocument.paragraphs.count, local: speech.localTTS.usesLocalEngine)) {
            await buildScrubMap()
        }
    }

    @ViewBuilder
    private var readingView: some View {
        // `contains` stops at the first character; trimming would copy the whole article HTML.
        if cleanedHTML.contains(where: { !$0.isWhitespace }) {
            // HTML path: do not touch `session.document` here — parsing is deferred
            // until Play / prepare. Avoids main-thread HTML walk on every open / progress write.
            HTMLReadingView(
                html: cleanedHTML,
                pageTitle: pageTitle,
                activeParagraphIndex: activeIndex,
                jumpMode: jumpMode,
                scrollRequest: scrollRequest,
                textInsets: textInsets
            ) { index in
                jump(to: index)
            }
        } else {
            ParagraphReadingView(
                document: readingDocument,
                activeParagraphIndex: activeIndex,
                jumpMode: jumpMode,
                scrollRequest: scrollRequest,
                textInsets: textInsets
            ) { index in
                jump(to: index)
            }
        }
    }

    /// Scrub capsule + listen row in the browser's bottom band: same margins, material, capsule,
    /// row height and ⋯ position as the address field + `[‹][›][⋯]`.
    private var bottomChrome: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            // Status text above the scrubber so skip / buffering never pushes it.
            listenStatusNotes

            // The back control sits left of the scrubber pill (same outside-capsule placement as
            // the search session's ✕), then the shared field capsule for scrub / Jump / bookmark.
            HStack(spacing: 10) {
                ReaderBackButton(origin: scrubControls.back, action: scrubControls.onBack)

                if let scrubMap {
                    let doc = readingDocument
                    let buffered = bufferedSpans(scrubMap)
                    PlayheadReader(speech: speech, resting: restingSpot) { spot in
                        ReaderScrubRow(
                            map: scrubMap,
                            position: Self.scrubFraction(scrubMap, document: doc, spot: spot),
                            buffered: buffered,
                            isSaved: scrubControls.isSaved,
                            jumpMode: jumpMode,
                            jumpEnabled: scrubControls.jumpEnabled,
                            onToggleJump: scrubControls.toggleJump,
                            onToggleSaved: scrubControls.toggleSaved,
                            onScrubPreview: { p in
                                scrubPreview = p
                                // The only programmatic scroll: following the user's own scrub.
                                if let p { scrollRequest = ReaderScrollRequest(index: p, token: (scrollRequest?.token ?? 0) + 1) }
                            },
                            onScrubCommit: seek(to:)
                        )
                    }
                } else {
                    // Holds the capsule's place until the scrub map is built, so nothing shifts.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .bottomChromeField()
                }
            }
            // The drag bubble spans the whole row, back control included.
            .readerScrubBubble()

            ListenControllerView(
                session: session,
                resumeParagraph: effectiveResume,
                resumeUTF16Offset: effectiveResumeOffset,
                onProgress: onProgress,
                trailing: listenTrailing,
                speech: speech
            )
        }
        .bottomChromeBand(bottomInset: safeInsets.bottom)
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // UI tests: the exact spot Play starts / plays from ("p=<paragraph> o=<offset in it>").
            if LaunchOptions.current.uiTesting {
                let doc = readingDocument
                PlayheadReader(speech: speech, resting: restingSpot) { spot in
                    Color.clear
                        .frame(width: 2, height: 2)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("Scrub position")
                        .accessibilityValue(Self.positionMarker(document: doc, spot: spot))
                        .accessibilityIdentifier("readerScrubOffset")
                }
            }
        }
        #endif
    }

    /// Buffering / Apple-fallback / language notes — above the scrubber so appearing text
    /// cannot move the scrub row.
    @ViewBuilder
    private var listenStatusNotes: some View {
        let isThisSession = speech.activeSessionID == session.id
        let languageNote = speech.languageResolution(detected: session.detectedLanguage).note
        if speech.showsListenDebugUI, speech.showBakeDebugOverlay {
            BakeDebugOverlay(speech: speech) {
                speech.showListenDebug = true
            }
        }
        if speech.showsListenDebugUI {
            HStack {
                Spacer(minLength: 0)
                Button {
                    speech.showBakeDebugOverlay.toggle()
                } label: {
                    Text(speech.showBakeDebugOverlay ? "Debug ▾" : "Debug")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(speech.showBakeDebugOverlay
                                           ? Color.accentColor.opacity(0.2)
                                           : Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("listenBakeDebugChip")
                .accessibilityLabel(speech.showBakeDebugOverlay ? "Hide bake debug" : "Show bake debug")
            }
            .padding(.horizontal, 8)
        }
        if isThisSession, speech.isBufferingNext {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing next…")
                    .accessibilityIdentifier("listenBufferingLabel")
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .accessibilityIdentifier("listenBuffering")
        } else if isThisSession, let renderNote = speech.renderNote {
            Text(renderNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("listenRenderNote")
        } else if let languageNote {
            Text(languageNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("listenLanguageNote")
        }
    }

    /// Where Play starts when this article isn't the loaded session (scrubbed / stored spot);
    /// nil while it is loaded, so the live playhead shows.
    private var restingSpot: PlayheadSpot? {
        isLoaded ? nil : PlayheadSpot(paragraph: effectiveResume, utf16Offset: effectiveResumeOffset)
    }

    #if DEBUG
    private static func positionMarker(document doc: ParagraphDocument, spot: PlayheadSpot) -> String {
        guard !doc.isEmpty else { return "p=0 o=0" }
        let start = doc.startUTF16Offset(forParagraph: spot.paragraph)
        return "p=\(spot.paragraph) o=\(max(0, (spot.utf16Offset ?? start) - start))"
    }
    #endif

    /// Scrubber fraction of `spot`. `ReaderScrubMap` keeps a spot inside its paragraph (< 1 of
    /// it), so the end of a paragraph never reads as the start of the next one.
    private static func scrubFraction(_ map: ReaderScrubMap, document doc: ParagraphDocument,
                                      spot: PlayheadSpot) -> Double {
        guard let offset = spot.utf16Offset, doc.paragraphs.indices.contains(spot.paragraph) else {
            return map.fraction(paragraph: spot.paragraph)
        }
        return map.fraction(paragraph: spot.paragraph, offset: offset - doc.startUTF16Offset(forParagraph: spot.paragraph))
    }

    /// Lighter "buffered" fill (like a video player): stretches of rendered audio, as scrubber
    /// fractions. Local engine only (Apple speaks live, so there's nothing to show).
    private func bufferedSpans(_ map: ReaderScrubMap) -> [ClosedRange<Double>] {
        guard let ready = bakeReadyIndices, !ready.isEmpty else { return [] }
        return map.spans(covering: ready)
    }

    /// Scrubber release: move the playhead to the sentence under the thumb. Playing keeps
    /// playing from that sentence; paused stays paused there (a real seek, not stop-and-reload);
    /// not loaded just moves where Play starts. Never touches another article that's playing.
    private func seek(to target: ReaderScrubMap.Target) {
        let doc = readingDocument
        let offset = doc.paragraphs.isEmpty ? 0 : doc.startUTF16Offset(forParagraph: target.paragraph) + target.offset
        localResume = target.paragraph
        localResumeOffset = offset
        if isLoaded {
            speech.seek(session, toUTF16Offset: offset)
            onProgress?(speech.currentParagraphIndex, speech.spokenUTF16Offset)
        } else {
            onProgress?(target.paragraph, offset)
        }
    }

    /// Sentence starts are the snap points for every engine (local playback starts mid-chunk,
    /// Apple from the character), so no chunk plan. Tokenized off the main thread.
    private func buildScrubMap() async {
        let paragraphs = readingDocument.paragraphs
        let map = await Task.detached(priority: .userInitiated) { ReaderScrubMap(paragraphs: paragraphs) }.value
        if !Task.isCancelled { scrubMap = map }
    }

    private func jump(to index: Int) {
        guard jumpMode else { return }
        jumpMode = false
        localResume = index
        localResumeOffset = nil
        speech.start(session, fromParagraph: index)
        onProgress?(speech.currentParagraphIndex, speech.spokenUTF16Offset)
    }

    /// Plain-text fallback only. Prefer speech-owned document when prepared.
    private var readingDocument: ParagraphDocument {
        isLoaded ? speech.document : session.document
    }

    /// Local-engine rendered paragraphs. `nil` on Apple.
    private var bakeReadyIndices: Set<Int>? {
        let count = readingDocument.paragraphs.count
        return speech.bakeReadyParagraphIndices(articleID: session.id, paragraphCount: count,
                                                detectedLanguage: session.detectedLanguage)
    }

    private struct ScrubMapKey: Hashable {
        let count: Int
        let local: Bool
    }
}

/// A playhead position: paragraph + document UTF-16 offset inside it (nil = paragraph start).
struct PlayheadSpot: Equatable {
    var paragraph: Int
    var utf16Offset: Int?
}

/// Hands `content` the live playhead — or `resting` when the article isn't the loaded session.
/// The live offset moves several times a second while playing; reading it here, in its own
/// body, keeps those redraws to `content` instead of the view that builds it. A resting spot
/// reads nothing live, so another article's playback doesn't redraw it either.
private struct PlayheadReader<Content: View>: View {
    let speech: SpeechController
    let resting: PlayheadSpot?
    @ViewBuilder let content: (PlayheadSpot) -> Content

    var body: some View {
        content(resting ?? PlayheadSpot(paragraph: speech.currentParagraphIndex,
                                        utf16Offset: speech.spokenUTF16Offset))
    }
}

/// What the bottom scrub row needs from the reader screen.
struct ReaderScrubControls {
    let isSaved: Bool
    let jumpEnabled: Bool
    let toggleJump: () -> Void
    let toggleSaved: () -> Void
    /// Where the back control (left of the scrubber pill) returns to.
    let back: ReaderOrigin
    let onBack: () -> Void
}

/// The reader's one close control, left of the scrubber pill (thumb reach): back to where the
/// reader was opened from, with that place's icon and name.
struct ReaderBackButton: View {
    let origin: ReaderOrigin
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: origin.backSystemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemBackground), in: Circle())
                .tapTarget(40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(origin.backLabel)
        .accessibilityIdentifier("readerClose")
    }
}

extension ReaderOrigin {
    /// The back control's icon: the place it returns to (same glyphs as the Library↔Browser swap).
    var backSystemImage: String {
        switch self {
        case .page: "globe"
        case .startPage: "house"
        case .library: "books.vertical"
        }
    }

    var backLabel: String {
        switch self {
        case .page: "Back to Website"
        case .startPage: "Back to Start Page"
        case .library: "Back to Library"
        }
    }
}

/// A one-shot "scroll this paragraph into view" (token changes per request).
struct ReaderScrollRequest: Equatable {
    let index: Int
    let token: Int
}
