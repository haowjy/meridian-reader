import SwiftUI
import UIKit

struct FaviconImage: View {
    let data: Data?
    var host: String = ""
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.1)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var monogram: String {
        host.first.map { String($0).uppercased() } ?? "?"
    }
}
