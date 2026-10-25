import SwiftUI

/// Shared card constants for `NowPlayingBar` and the clustered dock: artwork size, progress
/// height and the flat card surface (background, radius, no shadow).
enum PlayerCard {
    static let artworkSize: CGFloat = 40
    /// Matches `ScrubTrack`'s base track height (4 pt).
    static let progressHeight: CGFloat = 4
}

extension View {
    /// The flat card surface the bar and the dock's cards share: the reading palette's card fill (injecting
    /// `ReadingPalette.app` when no palette is set, so the fill, tile and progress colours are the
    /// same on every surface) and `Radius.card` corners.
    func playerCardSurface() -> some View {
        modifier(PlayerCardSurface())
    }
}

private struct PlayerCardSurface: ViewModifier {
    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    func body(content: Content) -> some View {
        content
            .environment(\.readingPalette, palette)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(palette.card)
            )
    }
}

private enum CardLayout {
    static let art: CGFloat = 36
    /// The title row's two round controls (Voice, bookmark).
    static let control: CGFloat = 36
    /// The scrubber row is `fieldControlSize` high with its track in the middle: pulled up so
    /// the track sits 64 pt from the card's top.
    static let scrubTop: CGFloat = 46
    static let labelsTop: CGFloat = 74
    static let scrubInset: CGFloat = 14
    static let transportTop: CGFloat = 92
}

/// The Reader's and Now Playing's player card on compact width: one glass card above the chrome's
/// row 2 (`ChromeLayout`'s `card` high; the chrome host supplies the glass and folds it into the
/// title chip). Plain values and slots, so both pages build the same card.
///
/// ```
/// [art]  Notes on Tides             (Voice) (Save)    art, title, site · time left, then two round controls
///        example.org · 9 min left
/// [━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━]     scrubber
/// 2:14                                   −9 min      elapsed, time left
///  Aa      ⏮        (▶)        ⏭         1×        transport: five equal slots
/// ```
///
/// Positions come from the mockup's card layer (`chrome.js`): it is a fixed 152 pt, not a flow
/// layout, so the scrubber's track sits 64 pt from the top and the disc 92 pt.
struct ReaderPlayerCard<Voice: View, Save: View, Scrub: View, Appearance: View, Speed: View>: View {
    let title: String
    /// Under the title: the site and time left, or a status note.
    var detail: String?
    var artwork: Image?
    var artworkLetter: String
    let playState: PlayState
    /// Under the scrubber's two ends.
    let elapsed: String
    let timeLeft: String
    var canSkip = true
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onPlayPause: () -> Void
    /// Long-press on play / pause (developer options: the listen debug panel); nil = none.
    var onPlayLongPress: (() -> Void)?
    @ViewBuilder var voice: Voice
    @ViewBuilder var save: Save
    /// The bare scrubber (`ReaderScrubRow` with `isCapsule: false`).
    @ViewBuilder var scrub: Scrub
    @ViewBuilder var appearance: Appearance
    @ViewBuilder var speed: Speed

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
                .padding(.horizontal, Spacing.s)
                .padding(.top, Spacing.s)
            scrub
                .padding(.horizontal, CardLayout.scrubInset)
                .padding(.top, CardLayout.scrubTop)
            HStack {
                Text(elapsed)
                Spacer(minLength: Spacing.s)
                Text(timeLeft)
            }
            .typeStyle(.caption)
            .monospacedDigit()
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, CardLayout.scrubInset)
            .padding(.top, CardLayout.labelsTop)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            transport
                .padding(.horizontal, Spacing.s)
                .padding(.top, CardLayout.transportTop)
        }
        .readerScrubBubble()
        .foregroundStyle(palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingPlayerCard")
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter, size: CardLayout.art)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .typeStyle(.caption)
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Two fixed 36 pt controls flush right (the mockup's card): the bookmark's own frame
            // is as wide as it is offered, so without a width it would share the row with the title.
            HStack(spacing: Spacing.xs) {
                voice
                save.frame(width: CardLayout.control)
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CardLayout.art)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            appearance.frame(maxWidth: .infinity)
            Button(action: onSkipBack) { Image(systemName: Icons.previous).font(BottomChrome.chromeGlyph) }
                .disabled(!canSkip)
                .accessibilityLabel("Previous paragraph")
                .frame(maxWidth: .infinity)
            PlayStateButton(state: playState, look: .disc, action: onPlayPause)
                .accessibilityLabel(playState == .playing ? Verbs.pause : Verbs.play)
                .accessibilityIdentifier("listenPlayPause")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onPlayLongPress?() },
                                     including: onPlayLongPress == nil ? .subviews : .all)
                .frame(maxWidth: .infinity)
            Button(action: onSkipForward) { Image(systemName: Icons.next).font(BottomChrome.chromeGlyph) }
                .disabled(!canSkip)
                .accessibilityLabel("Next paragraph")
                .frame(maxWidth: .infinity)
            speed.frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: BottomChrome.transportDiscSize)
    }
}

/// Voice in the Reader's and Now Playing's bottom player title row: a round field control (36 pt,
/// 44 pt to tap) trailing the title, on the card fill. Opens the article's or book's Voice picker
/// (`VoicePickerSheet` / `VoiceSelectionList`), the same list as Settings › Voice and ⋯ › Voice.
struct VoiceChromeButton: View {
    /// `readerVoice` or `nowPlayingVoice`.
    var identifier = "voiceChrome"
    let action: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        Button(action: action) {
            Image(systemName: Icons.voice)
                .foregroundStyle(reading?.ink ?? Palette.ink)
                .roundFieldControl(fill: BottomChrome.fieldFill(reading))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Verbs.voice)
    }
}

#if DEBUG
struct ReaderPlayerCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("Reader: not started") { card(state: .idle, elapsed: "0:00", detail: "example.org · 9 min") }
            PreviewState("Now Playing, saved") {
                card(state: .playing, elapsed: "2:14", detail: "example.org · 6 min left", saved: true)
                    .onReadingPreview(.sepia)
            }
            PreviewState("Paused, a status note") {
                card(state: .paused, elapsed: "2:14", detail: "Preparing next…").onReadingPreview(.dark)
            }
        }
    }

    private func card(state: PlayState, elapsed: String, detail: String, saved: Bool = false) -> some View {
        let map = ReaderScrubMap(paragraphs: (1...20).map { "Paragraph \($0)." })
        return ReaderPlayerCard(title: "Notes on Tides", detail: detail, artworkLetter: "N", playState: state,
                                elapsed: elapsed, timeLeft: "−9 min", onSkipBack: {}, onSkipForward: {}, onPlayPause: {}) {
            VoiceChromeButton(identifier: "previewVoice") {}
        } save: {
            SaveToggleButton(isSaved: saved, identifier: "preview", onToggle: {})
        } scrub: {
            ReaderScrubRow(map: map, position: 0.3, onScrubPreview: { _ in }, onScrubCommit: { _ in },
                           isCapsule: false) { EmptyView() }
        } appearance: {
            TextAppearanceButton(isOpen: false) {}
        } speed: {
            Text("1×").typeStyle(.caption).fieldTextFrame()
        }
        .frame(height: ChromeMetrics.card)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ChromeMetrics.barHeight / 2, style: .continuous))
    }
}

#Preview("ReaderPlayerCard - light", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.light) }
#Preview("ReaderPlayerCard - dark", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.dark) }
#Preview("ReaderPlayerCard - AX5", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.largestText) }
#endif
