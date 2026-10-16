import SwiftUI

/// Aa in the Reader's and Now Playing's top bars: opens the text appearance panel pointing at it,
/// bound to the app's `ReadingAppearance`, the store Settings › Reading edits too. The page under
/// it changes as you choose. The panel is drawn on the reading page's card colour.
struct TextAppearanceControl: View {
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.readingPalette) private var reading
    @State private var isOpen = false

    var body: some View {
        TextAppearanceButton(isOpen: isOpen) { isOpen.toggle() }
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                ReadingAppearancePanel(appearance: appearance)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground((reading ?? .app).card)
            }
    }
}

/// The panel bound to the store; it reads the palette afresh, so it follows a theme chosen in it.
private struct ReadingAppearancePanel: View {
    @Bindable var appearance: ReadingAppearance

    var body: some View {
        let accent = AppAppearance.shared.accent
        TextAppearancePanel(
            theme: $appearance.theme, font: $appearance.font, lineSpacing: $appearance.lineSpacing,
            textSize: appearance.textSizeModel, accent: accent
        )
        .readingSurface(appearance.palette(accent: accent))
    }
}

extension ReadingAppearance {
    /// The text size stepper's values and actions.
    var textSizeModel: TextSizeStepper.Model {
        TextSizeStepper.Model(label: ReadingTextSize.label(step: textSizeStep), canShrink: canShrinkText,
                              canGrow: canGrowText, shrink: shrinkText, grow: growText)
    }
}
