import SwiftUI

/// A big square-ish tile that starts something: a large symbol over a short label, on a soft filled
/// surface. Set side by side (two to a row) where a screen offers a few clearly separate ways in,
/// such as the empty Library's *Browse the Web* and *Import a Book*. `prominent` tints the surface
/// with the accent for the first choice; the rest sit on the neutral fill.
struct ActionTile: View {
    let title: String
    let symbol: String
    var prominent = false
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .glyphSize(Glyph.large)
                    .foregroundStyle(Palette.accent)
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, minHeight: ActionTile.minHeight)
            .background(prominent ? Palette.lit : Palette.chrome,
                        in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }

    /// Tall enough to read as a tile, not a button, two to a row on the smallest phone.
    static let minHeight: CGFloat = 132
}

#if DEBUG
struct ActionTileGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("two to a row") {
                HStack(spacing: Spacing.s) {
                    ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {}
                    ActionTile(title: "Import a Book", symbol: Icons.book) {}
                }
            }
        }
    }
}

#Preview("ActionTile · light", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.light) }
#Preview("ActionTile · dark", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.dark) }
#Preview("ActionTile · AX5", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.largestText) }
#endif
