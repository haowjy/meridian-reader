import SwiftUI

/// The only thing behind the chrome's pieces: a short gradient from clear to the colour of what is
/// under the chrome (the reading theme, a web page's own background, paper), so page text dissolves
/// before it reaches the top piece and the glass has something calm to blur. It is translucent
/// all the way: content shows through the pieces and between them.
struct ChromeFade: View {
    /// The top edge of the highest piece, in the chrome's box.
    let top: CGFloat
    let underColor: Color

    /// The gradient is clear at its top and reaches the page colour 70% of the way down.
    private static let solidAt = 0.7
    private static let opacity = 0.9

    var body: some View {
        let start = top - ChromeMetrics.fadeRise
        LinearGradient(stops: [.init(color: underColor.opacity(0), location: 0), .init(color: underColor, location: Self.solidAt)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(Self.opacity)
            .frame(height: ChromeMetrics.rowsHeight - start + ChromeHome.inset)
            // Down through the home indicator's strip (the bubble dips into it), and up
            // past the box's top by `fadeRise`.
            .offset(y: ChromeHome.inset)
            .frame(height: ChromeMetrics.rowsHeight, alignment: .bottom)
            .allowsHitTesting(false)
    }
}
