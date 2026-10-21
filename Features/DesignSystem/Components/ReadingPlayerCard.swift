import SwiftUI

/// The floating player card in the Reader and Now Playing bottom chrome: the article's artwork,
/// title, optional time-left detail and an optional scrub row.
///
/// ```
/// ╭─────────────────────────────────────────────╮
/// │ [art]  Notes on Tides          9 min left   │  <- title + time (trailing)
/// │ [-- scrubber, full width -------*---]   1x  │  <- `scrub` bare row; EmptyView in Reader
/// ╰─────────────────────────────────────────────╯
/// ```
///
/// Floating card (`floatingShadow`) in the reading page's card material. Pass `EmptyView()` for
/// `scrub` when not playing; with a scrub row (its own full-width row, C143) the card lifts the control row so play sits near 81% down.
struct ReadingPlayerCard<Scrub: View>: View {
    let title: String
    var timeDetail: String?
    var artwork: Image?
    var artworkLetter: String = ""
    @ViewBuilder var scrub: Scrub

    static var artworkSize: CGFloat { 40 }

    @Environment(\.readingPalette) private var reading

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        // C143: the scrubber gets its own full-width row under the title line, a bigger target that
        // also lifts the control row above the card to where the thumb rests.
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .center, spacing: Spacing.s) {
                ArtworkTile(image: artwork, letter: artworkLetter.isEmpty ? title : artworkLetter,
                            size: Self.artworkSize)
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
            scrub
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            if let reading { shape.fill(reading.card) } else { shape.fill(.regularMaterial) }
        }
        .floatingShadow(opacity: 0.14)
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
