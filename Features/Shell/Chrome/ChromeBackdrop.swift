import SwiftUI

/// The colour under the pieces. Glass floats on the content, so the page's own background is
/// opaque from the top of the top piece down and fades in over the fade's rise above it: page text
/// never shows through behind the pieces. Earlier iOS (the strip skin): one thick material behind
/// the rows, as tall as the layout, down through the safe area. Nothing in full screen.
struct ChromeBackdrop: View {
    let fade: ChromeGeometry.Fade?
    let skin: ChromeSkin
    let underColor: Color

    var body: some View {
        if let fade {
            switch skin {
            case .system:
                EmptyView()
            case .strip:
                Color.clear
                    .frame(height: fade.height)
                    .background(alignment: .bottom) { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
                    .overlay(alignment: .top) { Divider() }
                    .transition(.opacity)
            case .glass:
                Color.clear
                    .frame(height: fade.height)
                    .background(alignment: .bottom) { underColor.ignoresSafeArea(edges: .bottom) }
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [underColor.opacity(0), underColor], startPoint: .top, endPoint: .bottom)
                            .frame(height: fade.rise)
                            .offset(y: -fade.rise)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}
