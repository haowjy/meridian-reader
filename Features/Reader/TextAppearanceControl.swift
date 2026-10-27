import SwiftUI

/// Aa in the Reader's and Now Playing's top bars: opens the text appearance panel pointing at it,
/// bound to the app's `ReadingAppearance`, the same store and `ReadingAppearancePanel` as
/// Settings › Reading. The page under it changes as you choose. The panel is drawn on the reading
/// page's card colour and sized to `Panel.width` like the ⋯ menu.
struct TextAppearanceControl: View {
    @State private var isOpen = false
    /// Which edge of Aa the popover's arrow is on: `.top` under a top bar's Aa, `.bottom` for the
    /// player card's, which sits at the screen's foot and has no room below it.
    var arrowEdge: Edge = .top

    var body: some View {
        TextAppearanceButton(isOpen: isOpen) { isOpen.toggle() }
            .textAppearancePopover(isPresented: $isOpen, arrowEdge: arrowEdge)
    }
}

extension View {
    /// The text appearance panel as a popover pointing at this view (Aa, or an anchor standing in for
    /// it when a menu row opens the panel).
    func textAppearancePopover(isPresented: Binding<Bool>, arrowEdge: Edge = .top) -> some View {
        modifier(TextAppearancePopover(isPresented: isPresented, arrowEdge: arrowEdge))
    }
}

private struct TextAppearancePopover: ViewModifier {
    @Binding var isPresented: Bool
    let arrowEdge: Edge

    @Environment(\.readingAppearance) private var appearance
    @Environment(\.readingPalette) private var reading

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            ReadingAppearancePanel(appearance: appearance)
                .frame(width: Panel.width)
                .presentationCompactAdaptation(.popover)
                .presentationBackground((reading ?? .app).card)
        }
    }
}
