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

/// The Listen player card on compact width: one glass card at the foot of Listen (the cover band
/// supplies the glass; Listen never folds). Plain values and slots. It sizes to its rows.
///
/// ```
/// [art]  Notes on Tides…                  (🔖)    art, title (one line), site and time left; Save
///        example.org   9 min left
/// [━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━]   scrubber, no times
///            ⏮          (▶)          ⏭           transport (`NowPlayingTransport`'s grid)
/// ─────────────────────────────────────────────
///    Aa         1×         ♫          ⋯          tools: glyphs, no labels, equal shares
/// ```
struct ReaderPlayerCard<Save: View, Scrub: View, Transport: View, Tools: View>: View {
    let title: String
    /// Under the title, set apart by space (never a separator character): the site, then the time left,
    /// or one status note. The first part truncates first; the others never do.
    var detail: [String] = []
    var artwork: Image?
    var artworkLetter: String
    /// The title block's tap (art, title, site): nil leaves it inert. It never seeks.
    var origin: CardOrigin?
    /// Save, at the title row's trailing end (`SaveToggleButton`'s round face).
    @ViewBuilder var save: Save
    /// The bare scrubber (`ReaderScrubRow` with `isCapsule: false`).
    @ViewBuilder var scrub: Scrub
    /// Previous paragraph, play / pause, next paragraph (`ListenTransportView`).
    @ViewBuilder var transport: Transport
    /// The last row's small buttons, each in a `toolbarIconFrame` cell, so they share the row evenly.
    @ViewBuilder var tools: Tools

    @Environment(\.readingPalette) private var reading
    /// The gap between the site and the time left: `Spacing.s` (12 pt), growing with the caption as `DetailLine`'s does.
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var spacing = Spacing.s

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.s)
                .padding(.top, Spacing.s)
            scrub
                .padding(.horizontal, Spacing.s)
            transport
                .padding(.horizontal, Spacing.s)
            Divider()
                .overlay(palette.hairline)
                .padding(.horizontal, Spacing.s)
            HStack(spacing: 0) { tools }
                .padding(.horizontal, Spacing.xxs)
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
            save.fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: PlayerCard.artworkSize)
    }

    /// Art, title and detail: one Button (44 pt high, inside the block only) when the article has an origin.
    @ViewBuilder
    private var titleBlock: some View {
        let block = HStack(spacing: Spacing.xs) {
            ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter, size: PlayerCard.artworkSize)
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
}

/// Voice: opens the article's or book's Voice picker (`VoicePickerSheet` / `VoiceSelectionList`), the
/// same list as Settings › Voice and ⋯ › Voice. Its label is always "Voice", never a voice's name.
/// Round (36 pt, 44 pt to tap) trailing the title on regular width; a bare glyph cell
/// (`toolbarIconFrame`) in the compact player card's tools row.
struct VoiceChromeButton: View {
    /// `readerVoice` or `nowPlayingVoice`.
    var identifier = "voiceChrome"
    var round = true
    let action: () -> Void

    var body: some View {
        if round {
            RoundIconButton(symbol: Icons.voice, label: Verbs.voice, identifier: identifier, action: action)
        } else {
            Button(action: action) { Image(systemName: Icons.voice).toolbarIconFrame() }
                .buttonStyle(.plain)
                .accessibilityLabel(Verbs.voice)
                .accessibilityIdentifier(identifier)
        }
    }
}

#if DEBUG
struct ReaderPlayerCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("Not started") { card(state: .idle, detail: ["example.org", "9 min"]) }
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
        return ReaderPlayerCard(title: "Notes on Tides, and Why the Moon Pulls Twice a Day", detail: detail,
                                artworkLetter: "N") {
            SaveToggleButton(isSaved: saved, identifier: "preview", onToggle: {}, round: true)
        } scrub: {
            ReaderScrubRow(map: map, position: 0.3, onScrubPreview: { _ in }, onScrubCommit: { _ in },
                           isCapsule: false) { EmptyView() }
        } transport: {
            NowPlayingTransport(state: state, onSkipBack: {}, onSkipForward: {}, onPlayPause: {}) {
                EmptyView()
            } more: {
                EmptyView()
            }
        } tools: {
            TextAppearanceButton(isOpen: false, round: false) {}
            Text("1×").fieldTextFrame().frame(maxWidth: .infinity)
            VoiceChromeButton(identifier: "previewVoice", round: false) {}
            Image(systemName: Icons.more).toolbarIconFrame()
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ChromeMetrics.cardRadius, style: .continuous))
    }
}

#Preview("ReaderPlayerCard - light", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.light) }
#Preview("ReaderPlayerCard - dark", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.dark) }
#Preview("ReaderPlayerCard - AX5", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.largestText) }
#endif
