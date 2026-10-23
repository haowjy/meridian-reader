import SwiftUI

/// Aa in the Reader's and Now Playing's top bars: opens the text appearance panel pointing at it,
/// bound to the app's `ReadingAppearance`, the same store and `ReadingAppearancePanel` as
/// Settings › Reading. The page under it changes as you choose. The panel is drawn on the reading
/// page's card colour and sized to `Panel.width` like the ⋯ menu.
struct TextAppearanceControl: View {
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.readingPalette) private var reading
    @State private var isOpen = false

    var body: some View {
        TextAppearanceButton(isOpen: isOpen) { isOpen.toggle() }
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                ReadingAppearancePanel(appearance: appearance)
                    .frame(width: Panel.width)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground((reading ?? .app).card)
            }
    }
}
