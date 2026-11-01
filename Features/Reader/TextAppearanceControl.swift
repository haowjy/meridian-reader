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
