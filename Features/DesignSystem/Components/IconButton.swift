import SwiftUI

/// The app's icon button: a symbol in the reading page's colours, lit (`isOn`) in the accent.
/// Round (`round`), it sits on `roundFieldControl`'s face (36 pt, the field fill and a hairline,
/// 44 pt to tap), the highlight while lit: Aa and ☝︎ in a sheet's top bar, Voice beside the
/// player's title. Otherwise it is a bare glyph cell of a toolbar row (`toolbarIconFrame`): the
/// compact player card's tools (Aa, Voice). The bookmark (`SaveToggleButton`) draws the same two faces through
/// `iconButtonFace`, so every icon control reads alike.
struct IconButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var isOn = false
    var round = true
    let action: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isOn ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
                .iconButtonFace(round: round,
                                fill: isOn ? reading?.highlight ?? Palette.playingTint : BottomChrome.fieldFill(reading))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// An icon control's face: `roundFieldControl(fill:)` when `round`, else a toolbar cell.
    @ViewBuilder
    func iconButtonFace(round: Bool, fill: Color) -> some View {
        if round {
            roundFieldControl(fill: fill)
        } else {
            toolbarIconFrame()
        }
    }
}

#if DEBUG
struct IconButtonGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("round: Aa, ☝︎ off and on, Voice") {
                HStack(spacing: Spacing.s) {
                    IconButton(symbol: Icons.textAppearance, label: Verbs.textAppearance, identifier: "a") {}
                    IconButton(symbol: Icons.jump, label: "Listen from a paragraph", identifier: "b") {}
                    IconButton(symbol: Icons.jumpOn, label: "Listen from a paragraph", identifier: "c", isOn: true) {}
                    IconButton(symbol: Icons.voice, label: Verbs.voice, identifier: "d") {}
                }
            }
            PreviewState("toolbar cells: Aa lit, Voice") {
                HStack(spacing: 0) {
                    IconButton(symbol: Icons.textAppearance, label: Verbs.textAppearance, identifier: "e", isOn: true,
                               round: false) {}
                    IconButton(symbol: Icons.voice, label: Verbs.voice, identifier: "f", round: false) {}
                }
            }
            PreviewState("on a sepia reading page") {
                HStack(spacing: Spacing.s) {
                    IconButton(symbol: Icons.textAppearance, label: Verbs.textAppearance, identifier: "g", isOn: true) {}
                    IconButton(symbol: Icons.jump, label: "Listen from a paragraph", identifier: "h") {}
                }
                .onReadingPreview(.sepia)
            }
        }
    }
}

#Preview("IconButton · light", traits: .sizeThatFitsLayout) { IconButtonGallery().previewVariant(.light) }
#Preview("IconButton · dark", traits: .sizeThatFitsLayout) { IconButtonGallery().previewVariant(.dark) }
#Preview("IconButton · AX5", traits: .sizeThatFitsLayout) { IconButtonGallery().previewVariant(.largestText) }
#endif
