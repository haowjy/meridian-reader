import SwiftUI

/// The app's round icon button: a symbol on `roundFieldControl`'s face (36 pt, the field fill and
/// a hairline, the chrome glyph's weight), in the reading page's colours. Lit (`isOn`) it takes
/// the accent on the highlight. Voice, Aa and ☝︎ are this; the bookmark (`SaveToggleButton`, its
/// `round` face) and the speed use the same face, so every round control reads alike.
struct RoundIconButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var isOn = false
    let action: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isOn ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                .roundFieldControl(fill: isOn ? reading?.highlight ?? Palette.playingTint : BottomChrome.fieldFill(reading))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
