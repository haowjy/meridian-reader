import SwiftUI

/// A 3 pt progress capsule (mini player, Continue cards and rows, the Now Playing bar).
struct ThinProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.secondaryInk.opacity(0.22))
                Capsule().fill(Palette.accent).frame(width: g.size.width * min(max(0, value), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
