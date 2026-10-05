import SwiftUI

/// What is playing, at the top of Now Playing's text (it scrolls with the text): the artwork, the
/// title, and "site · N min left". Drawn on the player palette.
///
/// ```
/// ┌──────────────────────────────────────────┐
/// │ ┌──┐  Seven-Day Yield: Definition         │
/// │ │I │  example.com · 12 min left           │
/// │ └──┘                                      │
/// └──────────────────────────────────────────┘
/// ```
struct TitleCard: View {
    let title: String
    /// "example.com · 12 min left", or "✓ Finished".
    let detail: String
    var artwork: Image?
    /// On the tile when there is no artwork.
    let artworkLetter: String

    /// The artwork tile's side. Fixed, like the other artwork sizes.
    static let artworkSize: CGFloat = 56

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the text takes the whole width, under the artwork.
        let large = dynamicTypeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(spacing: Spacing.s))
        layout {
            ArtworkTile(image: artwork, letter: artworkLetter, size: Self.artworkSize)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .typeStyle(.row, weight: .bold)
                    .foregroundStyle(Palette.playerInk)
                    .lineLimit(large ? nil : 3)
                Text(detail)
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.playerSecondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.s)
        .background(Palette.playerCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .environment(\.onPlayerPalette, true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nowPlayingTitleCard")
    }
}

#if DEBUG
struct TitleCardGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("a page, letter tile") {
                TitleCard(title: "Seven-Day Yield: Definition, Calculation", detail: "example.com · 12 min left",
                          artworkLetter: "example.com")
                    .onPlayerPreview(Palette.playerBackground)
            }
            PreviewState("a chapter, artwork") {
                TitleCard(title: "Chapter 12", detail: "Pride and Prejudice · 15 min left",
                          artwork: Image(systemName: "book.closed.fill"), artworkLetter: "P")
                    .onPlayerPreview(Palette.playerBackground)
            }
            PreviewState("finished, long title") {
                TitleCard(title: "Notes on the Tides of the Northern Coast, and the Tables Fishermen Keep",
                          detail: "✓ Finished", artworkLetter: "N")
                    .onPlayerPreview(Palette.playerBackground)
            }
        }
    }
}

#Preview("TitleCard · light", traits: .sizeThatFitsLayout) { TitleCardGallery().previewVariant(.light) }
#Preview("TitleCard · dark", traits: .sizeThatFitsLayout) { TitleCardGallery().previewVariant(.dark) }
#Preview("TitleCard · AX5", traits: .sizeThatFitsLayout) { TitleCardGallery().previewVariant(.largestText) }
#endif
