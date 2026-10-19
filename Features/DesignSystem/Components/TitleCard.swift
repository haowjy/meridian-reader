import SwiftUI

/// What is playing, at the top of Now Playing's text (it scrolls with the text): the artwork, the
/// title (none for a page without one), and the site and time left as separate parts
/// (`DetailLine`). Drawn in the reading page's colours (`palette`: it is hosted inside the page's
/// web view, out of the sheet's environment, so it is handed them).
///
/// ```
/// ┌──────────────────────────────────────────┐
/// │ ┌──┐  Seven-Day Yield: Definition         │
/// │ │I │  example.com   12 min left           │
/// │ └──┘                                      │
/// └──────────────────────────────────────────┘
/// ```
struct TitleCard: View {
    let title: String?
    /// ["example.com", "12 min left"], or [.finished].
    let detail: [DetailPart]
    var artwork: Image?
    /// On the tile when there is no artwork.
    let artworkLetter: String
    let palette: ReadingPalette

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
                if let title {
                    Text(title)
                        .typeStyle(.row, weight: .bold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(large ? nil : 3)
                }
                DetailLine(parts: detail)
                    .typeStyle(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.s)
        .background(palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .readingSurface(palette)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nowPlayingTitleCard")
    }
}

#if DEBUG
struct TitleCardGallery: View {
    private static func palette(_ theme: ReadingTheme) -> ReadingPalette { theme.palette(accent: .jade) }

    var body: some View {
        PreviewGallery {
            PreviewState("a page, letter tile") {
                TitleCard(title: "Seven-Day Yield: Definition, Calculation", detail: ["example.com", "12 min left"],
                          artworkLetter: "example.com", palette: Self.palette(.matchApp))
                    .onReadingPreview(.matchApp)
            }
            PreviewState("a chapter, artwork") {
                TitleCard(title: "Chapter 12", detail: ["Pride and Prejudice", "15 min left"],
                          artwork: Image(systemName: Icons.book), artworkLetter: "P", palette: Self.palette(.sepia))
                    .onReadingPreview(.sepia)
            }
            PreviewState("a page with no title") {
                TitleCard(title: nil, detail: ["example.com", "12 min left"], artworkLetter: "example.com",
                          palette: Self.palette(.dark))
                    .onReadingPreview(.dark)
            }
            PreviewState("finished, long title") {
                TitleCard(title: "Notes on the Tides of the Northern Coast, and the Tables Fishermen Keep",
                          detail: [.finished], artworkLetter: "N", palette: Self.palette(.black))
                    .onReadingPreview(.black)
            }
        }
    }
}

#Preview("TitleCard · light", traits: .sizeThatFitsLayout) { TitleCardGallery().previewVariant(.light) }
#Preview("TitleCard · dark", traits: .sizeThatFitsLayout) { TitleCardGallery().previewVariant(.dark) }
#Preview("TitleCard · AX5", traits: .sizeThatFitsLayout) { TitleCardGallery().previewVariant(.largestText) }
#endif
