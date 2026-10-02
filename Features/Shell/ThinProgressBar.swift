import SwiftUI

/// A 3 pt progress capsule (mini player, Continue listening rows).
struct ThinProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22))
                Capsule().fill(Color.accentColor).frame(width: g.size.width * min(max(0, value), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
