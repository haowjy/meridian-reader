import SwiftUI

/// Artwork: a site icon, a book's cover, or a letter tile when there is no image. The only letter
/// tile in the app: rows, the Now Playing bar and title card, Favorites, search suggestions and a
/// folder header all draw this one. Corners scale with the size (an icon's proportions; a cover's
/// are squarer), so tiles look alike at any size.
struct ArtworkTile: View {
    /// The image, when there is one (a favicon, a cover).
    var image: Image?
    /// What the letter stands for (a page's `PageTitle.artworkLetter`, a folder's name): the tile
    /// shows its first letter or digit, a leading "www." skipped ("www.example.com" → "E").
    let letter: String
    var size: CGFloat = 36
    /// A book cover's proportions (taller than wide) instead of a square.
    var isCover = false
    /// The tile behind an image (a transparent favicon). With no image the letter sits on
    /// `placeholderTile` instead, which reads on chrome and paper alike.
    var fill = Palette.chrome

    @Environment(\.readingPalette) private var reading

    var body: some View {
        let height = isCover ? size * 1.45 : size
        let shape = RoundedRectangle(cornerRadius: size * (isCover ? 0.06 : 0.22), style: .continuous)
        ZStack {
            // On the reading page the tile takes its track, so it sits quietly in any reading theme.
            shape.fill(reading.map { $0.track } ?? (image == nil ? Palette.placeholderTile : fill))
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                // Sized by the tile's height, so a cover's letter matches a square tile's in a row.
                Text(Self.initial(of: letter))
                    .font(.system(size: height * 0.45, weight: .semibold))
                    .foregroundStyle(reading?.secondaryInk ?? Palette.placeholderInk)
            }
        }
        .frame(width: size, height: height)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    /// "investopedia.com" → "I", "www.example.com" → "E", "“Quoted” title" → "Q"; " " → "".
    static func initial(of text: String) -> String {
        let trimmed = text.hasPrefix("www.") ? text.dropFirst(4) : Substring(text)
        return trimmed.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? ""
    }
}
