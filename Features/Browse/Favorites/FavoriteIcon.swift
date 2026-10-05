import SwiftUI
import UIKit

/// Site icon on a rounded tile, or a colored letter tile when there's no (usable) icon.
struct FavoriteIcon: View {
    let page: Page
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            if let image = icon {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Palette.chrome)
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * 0.56, height: size * 0.56)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(tint.gradient)
                Text(letter)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
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

    private var tint: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .brown]
        let hash = page.byline.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}
