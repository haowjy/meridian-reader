import SwiftUI

/// Aa in the regular-width Reader's and Now Playing's top bars: opens the text appearance panel pointing
/// at it, bound to the app's `ReadingAppearance`, the same store and `ReadingAppearancePanel` as
/// Settings › Reading. The page under it changes as you choose. The panel is drawn on the reading
/// page's card colour and sized to `Panel.width` like the ⋯ menu. Compact width's is the top group's
/// (`ReadingTopGroup`).
struct TextAppearanceControl: View {
    @State private var isOpen = false

    var body: some View {
        IconButton(symbol: Icons.textAppearance, label: Verbs.textAppearance, identifier: "textAppearanceButton",
                   isOn: isOpen) { isOpen.toggle() }
            .textAppearancePopover(isPresented: $isOpen)
    }
}

extension View {
    /// The text appearance panel as a popover pointing at this view (Aa), its arrow on its top edge.
    func textAppearancePopover(isPresented: Binding<Bool>) -> some View {
        modifier(TextAppearancePopover(isPresented: isPresented))
    }
}

private struct TextAppearancePopover: ViewModifier {
    @Binding var isPresented: Bool

    @Environment(\.readingAppearance) private var appearance
    @Environment(\.readingPalette) private var reading

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            ReadingAppearancePanel(appearance: appearance)
                .frame(width: Panel.width)
                .presentationCompactAdaptation(.popover)
                .presentationBackground((reading ?? .app).card)
        }
    }
}
