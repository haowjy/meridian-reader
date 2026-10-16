import SwiftUI
import UIKit

/// Site icon on a rounded tile, or a letter tile in the app's colour (`placeholderTile`, as every
/// artwork without an image) when there's no (usable) icon.
struct FavoriteIcon: View {
    let page: Page
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            if let image = icon {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.chrome)
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.56, height: size * 0.56)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.placeholderTile)
                Text(letter)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.placeholderInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var icon: UIImage? {
        // Tiny 16 px icons look smeared on a big tile; the letter tile reads better.
        guard FaviconFetcher.isTileSized(page.artworkData),
              let data = page.artworkData else { return nil }
        return UIImage(data: data)
    }

    private var letter: String {
        let source = page.title.first(where: { $0.isLetter || $0.isNumber })
            ?? page.byline.replacingOccurrences(of: "www.", with: "").first
        return source.map { String($0).uppercased() } ?? "?"
    }
}
