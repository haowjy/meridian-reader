import SwiftUI

/// The only thing behind the chrome's pieces: a short gradient from clear to the colour of what is
/// under the chrome (the reading theme, a web page's own background, paper), so page text dissolves
/// before it reaches the top piece and the glass has something calm to blur. It is translucent
/// all the way: content shows through the pieces and between them.
struct ChromeFade: View {
    /// The top edge of the highest piece, in the chrome's box.
    let top: CGFloat
    let underColor: Color
    /// How far the strip has come up (0 to 1): the strip has no glass, so the fade turns solid under it.
    var strip: CGFloat = 0

    /// The gradient is clear at its top and reaches the page colour 70% of the way down.
    private static let solidAt = 0.7
    private static let opacity = 0.9

    var body: some View {
        let start = top - ChromeMetrics.fadeRise
        // With the strip up the page colour is solid by the strip's top, so its text sits on calm ground.
        let stripTop = ChromeMetrics.fadeRise / max(ChromeMetrics.readerFootprint - start, 1)
        let solidAt = Self.solidAt + (min(stripTop, Self.solidAt) - Self.solidAt) * strip
        LinearGradient(stops: [.init(color: underColor.opacity(0), location: 0), .init(color: underColor, location: solidAt)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(Self.opacity + (1 - Self.opacity) * strip)
            .frame(height: ChromeMetrics.readerFootprint - start)
            // Down through the home indicator's area; up beyond the box when the Reader's card is tall.
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(height: ChromeMetrics.readerFootprint, alignment: .bottom)
            .allowsHitTesting(false)
    }
}
