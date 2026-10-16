import SwiftUI

/// Artwork: a site icon, a book's cover, or a letter tile when there is no image. Corners scale
/// with the size (an icon's proportions; a cover's are squarer), so tiles look alike at any size.
struct ArtworkTile: View {
    /// The image, when there is one (a favicon, a cover).
    var image: Image?
    /// Shown on the tile when there is no image: usually the first letter of the site or title.
    let letter: String
    var size: CGFloat = 36
    /// A book cover's proportions (taller than wide) instead of a square.
    var isCover = false
    /// The tile behind an image (a transparent favicon). With no image the letter sits on
    /// `placeholderTile` instead, which reads on chrome and paper alike.
    var fill = Palette.chrome

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * (isCover ? 0.06 : 0.22), style: .continuous)
        ZStack {
            // On the reading page the tile takes its track, so it sits quietly in any reading theme.
            shape.fill(reading.map { $0.track } ?? (image == nil ? Palette.placeholderTile : fill))
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Text(letter.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(reading?.secondaryInk ?? Palette.placeholderInk)
            }
        }
        .frame(width: size, height: isCover ? size * 1.45 : size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
