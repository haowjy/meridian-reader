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
/// supplies the glass; Listen never folds). Plain values and slots. It sizes to its rows; nothing
/// divides them but space.
///
/// ```
/// Notes on Tides, and Why the Moon Pul…  (🔖)    title (one line); Save
/// example.org                   6 min left    site leading, time left trailing (or one note)
/// ━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━   scrubber, no times
/// 1×        ⏮       (  ▶  )       ⏭    Voice   `leading` and `trailing` at the margins, the
///                                             transport centred between them
/// ```
struct ReaderPlayerCard<Save: View, Scrub: View, Transport: View, Leading: View, Trailing: View>: View {
    let title: String
    /// Under the title, set apart by space (never a separator character): the site, then the time left
    /// at the trailing end, or one status note. The first part truncates; the others never do.
    var detail: [String] = []
    /// The title's tap: nil leaves it inert. It never seeks.
    var origin: CardOrigin?
    /// Save, at the title row's trailing end (`SaveToggleButton`'s round face).
    @ViewBuilder var save: Save
    /// The scrubber (`ReaderScrubRow`).
    @ViewBuilder var scrub: Scrub
    /// Previous paragraph, play / pause, next paragraph (`ListenTransportView`, `card` size).
    @ViewBuilder var transport: Transport
    /// The small control at the leading margin (speed): a `playerCardTool`.
    @ViewBuilder var leading: Leading
    /// The one at the trailing margin (Voice): a `playerCardTool`.
    @ViewBuilder var trailing: Trailing

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            detailRow
            scrub
                // The track sits mid-row; its touch area may reach under the text above and the gap below.
                .padding(.vertical, -Spacing.xxs)
            controls
        }
        .padding(.horizontal, Spacing.s)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.xs)
        // The whole card takes a tap, so one on its title or its blank corners never reaches the
        // page behind it (a tap there hides the chrome) and nothing in it seeks.
        .contentShape(Rectangle())
        .onTapGesture {}
        .readerScrubBubble(aboveContainer: true)
        .foregroundStyle(palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingPlayerCard")
    }

    private var titleRow: some View {
        HStack(spacing: Spacing.xs) {
            titleText
            save.fixedSize()
        }
        .frame(minHeight: Control.small)
    }

    /// The title, a Button to its origin when it has one (44 pt to tap, the row's width before Save).
    @ViewBuilder
    private var titleText: some View {
        let text = Text(title)
            .typeStyle(.row, weight: .semibold)
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let origin {
            Button(action: origin.open) {
                text
                    .frame(minHeight: Control.tap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(origin.label)
            .accessibilityIdentifier("listenOrigin")
            .padding(.vertical, -Spacing.xxs)
        } else {
            text
        }
    }

    /// The site leading and the time left trailing; a single part (a note, "Finished") leading.
    @ViewBuilder
    private var detailRow: some View {
        if !detail.isEmpty {
            HStack(spacing: Spacing.s) {
                Text(detail[0]).lineLimit(1)
                Spacer(minLength: 0)
                ForEach(Array(detail.dropFirst().enumerated()), id: \.offset) { _, part in
                    Text(part).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
            }
            .typeStyle(.caption)
            .foregroundStyle(palette.secondaryInk)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DetailLine.accessibilityLabel(detail))
        }
    }

    /// The tools at the margins and the transport centred between them.
    private var controls: some View {
        ZStack {
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 0)
                trailing
            }
            transport
        }
    }
}

extension View {
    /// A player card tool (speed, Voice): a `Control.tap` square, its glyph or text centred.
    func playerCardTool() -> some View {
        frame(width: Control.tap, height: Control.tap)
            .contentShape(Rectangle())
    }
}

#if DEBUG
struct ReaderPlayerCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("Not started") { card(state: .idle, detail: ["example.org", "9 min"]) }
            PreviewState("Listen, saved") {
                card(state: .playing, detail: ["example.org", "6 min left"], saved: true)
                    .onReadingPreview(.sepia)
            }
            PreviewState("Paused, a status note") {
                card(state: .paused, detail: ["Preparing next…"]).onReadingPreview(.dark)
            }
            PreviewState("Finished") { card(state: .idle, detail: ["Finished"]) }
        }
    }

    private func card(state: PlayState, detail: [String], saved: Bool = false) -> some View {
        let map = ReaderScrubMap(paragraphs: (1...20).map { "Paragraph \($0)." })
        return ReaderPlayerCard(title: "Notes on Tides, and Why the Moon Pulls Twice a Day", detail: detail) {
            SaveToggleButton(isSaved: saved, identifier: "preview", onToggle: {}, round: true)
        } scrub: {
            ReaderScrubRow(map: map, position: 0.3, onScrubPreview: { _ in }, onScrubCommit: { _ in }) {
                EmptyView()
            }
        } transport: {
            NowPlayingTransport(state: state, size: .card, onSkipBack: {}, onSkipForward: {}, onPlayPause: {})
        } leading: {
            Text("1×").fieldTextFrame().playerCardTool()
        } trailing: {
            IconButton(symbol: Icons.voice, label: Verbs.voice, identifier: "previewVoice", round: false) {}
                .playerCardTool()
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
    }
}

#Preview("ReaderPlayerCard - light", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.light) }
#Preview("ReaderPlayerCard - dark", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.dark) }
#Preview("ReaderPlayerCard - AX5", traits: .sizeThatFitsLayout) { ReaderPlayerCardGallery().previewVariant(.largestText) }
#endif
