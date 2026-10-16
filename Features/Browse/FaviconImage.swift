import SwiftUI
import UIKit

/// A site's icon on a `chrome` tile, or its letter: the search suggestions' leading column.
struct FaviconImage: View {
    let data: Data?
    var host: String = ""
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Palette.chrome)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.1)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var monogram: String {
        host.first.map { String($0).uppercased() } ?? "?"
    }
}
