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

    @Environment(\.onPlayerPalette) private var onPlayer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * (isCover ? 0.06 : 0.22), style: .continuous)
        ZStack {
            shape.fill(onPlayer ? Palette.playerTrack : Palette.chrome)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Text(letter.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(onPlayer ? Palette.playerSecondaryInk : Palette.secondaryInk)
            }
        }
        .frame(width: size, height: isCover ? size * 1.45 : size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
