import SwiftUI

/// Shared card constants for `NowPlayingBar` and `ReadingPlayerCard`: artwork size, progress
/// height and the flat card surface (background, radius, no shadow).
enum PlayerCard {
    static let artworkSize: CGFloat = 40
    /// Matches `ScrubTrack`'s base track height (4 pt).
    static let progressHeight: CGFloat = 4
}

extension View {
    /// The flat card surface both player cards share: the reading palette's card fill (injecting
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

/// The player card in the Reader and Now Playing bottom chrome: the article's artwork, title,
/// optional time-left detail and an optional scrub row, on the reading page's card colour. Sits
/// inside `ReadingBottomBand`; the scrub area always reserves `fieldControlSize` height so the
/// card is the same size in both screens, whether the scrub row is a live bar, a placeholder or
/// empty.
///
/// ```
/// ╭─────────────────────────────────────────────╮
/// │ [art]  Notes on Tides          9 min left   │  <- title + time (trailing)
/// │ [-- scrubber, full width -------*---]   1x  │  <- `scrub` bare row; EmptyView in Reader
/// ╰─────────────────────────────────────────────╯
/// ```
struct ReadingPlayerCard<Scrub: View>: View {
    let title: String
    var timeDetail: String?
    var artwork: Image?
    var artworkLetter: String = ""
    @ViewBuilder var scrub: Scrub

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.s) {
                ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter,
                            size: PlayerCard.artworkSize)
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let timeDetail {
                    Text(timeDetail)
                        .typeStyle(.caption)
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            ZStack(alignment: .leading) {
                Color.clear.frame(height: BottomChrome.fieldControlSize)
                scrub
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .playerCardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingPlayerCard")
    }
}

#if DEBUG
struct ReadingPlayerCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("Reader: title + time, no scrub") {
                ReadingPlayerCard(title: "Seven-Day Yield: Definition, Calculation",
                                  timeDetail: "9 min", artworkLetter: "example.com") { EmptyView() }
                    .onReadingPreview(.matchApp)
            }
            PreviewState("Now Playing: with scrub") {
                let map = ReaderScrubMap(paragraphs: (1...20).map { "Paragraph \($0)." })
                ReadingPlayerCard(title: "Chapter 12: Hunsford", timeDetail: "9 min left",
                                  artworkLetter: "P") {
                    ReaderScrubRow(map: map, position: 0.3, onScrubPreview: { _ in },
                                   onScrubCommit: { _ in }, isCapsule: false) {
                        Text("1x").typeStyle(.caption).foregroundStyle(Palette.ink).fieldTextFrame()
                    }
                }
                .onReadingPreview(.sepia)
            }
            PreviewState("Finished, artwork") {
                ReadingPlayerCard(title: "Notes on Tides", timeDetail: "Finished",
                                  artwork: Image(systemName: "book.fill"), artworkLetter: "N") { EmptyView() }
                    .onReadingPreview(.dark)
            }
        }
    }
}

#Preview("ReadingPlayerCard - light", traits: .sizeThatFitsLayout) { ReadingPlayerCardGallery().previewVariant(.light) }
#Preview("ReadingPlayerCard - dark", traits: .sizeThatFitsLayout) { ReadingPlayerCardGallery().previewVariant(.dark) }
#Preview("ReadingPlayerCard - AX5", traits: .sizeThatFitsLayout) { ReadingPlayerCardGallery().previewVariant(.largestText) }
#endif
