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

/// What the card's title block opens when it is tapped: the article's place in the Library or its page.
struct CardOrigin {
    /// "Open <title> in Library" / "Open <title> in Browser".
    let label: String
    let open: () -> Void
}

private enum CardLayout {
    static let art: CGFloat = 36
    /// The scrubber row is `fieldControlSize` high with its track in the middle: pulled up so
    /// the track sits 64 pt from the card's top. (Its touch area stops 2 pt short of the row's top
    /// and bottom, `ReaderScrubRow`: the title row above and the transport below keep their taps.)
    static let scrubTop: CGFloat = 46
    static let scrubInset: CGFloat = 14
    static let transportTop: CGFloat = 80
}

/// The Reader's and Now Playing's player card on compact width: one glass card above the chrome's
/// row 2 (`ChromeLayout`'s `card` high; the chrome host supplies the glass; Listen never folds). Plain values and slots, so both pages build the same card.
///
/// ```
/// [art]  Notes on Tides             (Voice) (Save)    art, title, site and time left, then two round controls
///        example.org   9 min left
/// [━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━]     scrubber, nothing under it (no times)
///  Aa      ⏮        (▶)        ⏭         1×        transport: five equal slots
/// ```
///
/// Positions come from the mockup's card layer (`chrome.js`): it is a fixed 140 pt, not a flow
/// layout, so the scrubber's track sits 64 pt from the top and the disc 80 pt.
struct ReaderPlayerCard<Voice: View, Save: View, Scrub: View, Appearance: View, Speed: View>: View {
    let title: String
    /// Under the title, set apart by space (never a separator character): the site, then the time left,
    /// or one status note. The first part truncates first; the others never do.
    var detail: [String] = []
    var artwork: Image?
    var artworkLetter: String
    let playState: PlayState
    var canSkip = true
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    let onPlayPause: () -> Void
    /// Long-press on play / pause (developer options: the listen debug panel); nil = none.
    var onPlayLongPress: (() -> Void)?
    /// The title block's tap (art, title, site): nil leaves it inert. It never seeks.
    var origin: CardOrigin?
    @ViewBuilder var voice: Voice
    @ViewBuilder var save: Save
    /// The bare scrubber (`ReaderScrubRow` with `isCapsule: false`).
    @ViewBuilder var scrub: Scrub
    @ViewBuilder var appearance: Appearance
    @ViewBuilder var speed: Speed

    @Environment(\.readingPalette) private var reading
    /// The gap between the site and the time left: `Spacing.s` (12 pt), growing with the caption as `DetailLine`'s does.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var spacing = Spacing.s

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
                .padding(.horizontal, Spacing.s)
                .padding(.top, Spacing.s)
            scrub
                .padding(.horizontal, CardLayout.scrubInset)
                .padding(.top, CardLayout.scrubTop)
            transport
                .padding(.horizontal, Spacing.s)
                .padding(.top, CardLayout.transportTop)
        }
        // The whole card takes a tap, so one on its title block or its blank corners never reaches the
        // page behind it (a tap there hides the chrome) and nothing in it seeks.
        .contentShape(Rectangle())
        .onTapGesture {}
        .readerScrubBubble(aboveContainer: true)
        .foregroundStyle(palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingPlayerCard")
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            titleBlock
            // Two round controls (36 pt each, the app's one round icon face) flush right.
            HStack(spacing: Spacing.xs) {
                voice
                save
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CardLayout.art)
    }

    /// Art, title and detail: one Button (44 pt high, inside the block only) when the article has an origin.
    @ViewBuilder
    private var titleBlock: some View {
        let block = HStack(spacing: Spacing.xs) {
            ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter, size: CardLayout.art)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if !detail.isEmpty {
                    HStack(spacing: spacing) {
                        ForEach(Array(detail.enumerated()), id: \.offset) { index, part in
                            if index == 0 {
                                Text(part).lineLimit(1)
                            } else {
                                Text(part).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    .typeStyle(.caption)
                    .foregroundStyle(palette.secondaryInk)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(DetailLine.accessibilityLabel(detail))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let origin {
            Button(action: origin.open) {
                block
                    .frame(minHeight: ChromeMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(origin.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("listenOrigin")
        } else {
            block
        }
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

    var body: some View {
        RoundIconButton(symbol: Icons.voice, label: Verbs.voice, identifier: identifier, action: action)
    }
}

#if DEBUG
struct ReaderPlayerCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("Reader: not started") { card(state: .idle, detail: ["example.org", "9 min"]) }
            PreviewState("Now Playing, saved") {
                card(state: .playing, detail: ["example.org", "6 min left"], saved: true)
                    .onReadingPreview(.sepia)
            }
            PreviewState("Paused, a status note") {
                card(state: .paused, detail: ["Preparing next…"]).onReadingPreview(.dark)
            }
        }
    }

    private func card(state: PlayState, detail: [String], saved: Bool = false) -> some View {
        let map = ReaderScrubMap(paragraphs: (1...20).map { "Paragraph \($0)." })
        return ReaderPlayerCard(title: "Notes on Tides", detail: detail, artworkLetter: "N", playState: state,
                                onSkipBack: {}, onSkipForward: {}, onPlayPause: {}) {
            VoiceChromeButton(identifier: "previewVoice") {}
        } save: {
            SaveToggleButton(isSaved: saved, identifier: "preview", onToggle: {})
        } scrub: {
            ReaderScrubRow(map: map, position: 0.3, onScrubPreview: { _ in }, onScrubCommit: { _ in },
                           isCapsule: false) { EmptyView() }
        } appearance: {
            TextAppearanceButton(isOpen: false) {}
        } speed: {
            Text("1×").foregroundStyle(Palette.ink).roundFieldText(fill: Palette.chrome)
        }
        .frame(height: ChromeMetrics.card)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ChromeMetrics.cardRadius, style: .continuous))
    }
}

#Preview("ReaderPlayerCard - light", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.light) }
#Preview("ReaderPlayerCard - dark", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.dark) }
#Preview("ReaderPlayerCard - AX5", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.largestText) }
#endif
