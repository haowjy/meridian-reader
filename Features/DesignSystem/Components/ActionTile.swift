import SwiftUI

/// A big square-ish tile that starts something: a large symbol over a short label, on a soft filled
/// surface. Set side by side (two to a row) where a screen offers a few clearly separate ways in,
/// such as every empty screen's *Browse the Web*, *Import a File*, *Paste Text* and *Add a Link*. `prominent` tints the surface
/// with the accent for the first choice; the rest sit on the neutral fill.
struct ActionTile: View {
    let title: String
    let symbol: String
    var prominent = false
    var identifier: String?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the accessibility sizes tiles stack, one to a row: the symbol goes beside the label and
        // the tile is as tall as they are, so a screen's tiles and its heading fit without scrolling.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(HStackLayout(spacing: Spacing.s)) : AnyLayout(VStackLayout(spacing: Spacing.s))
        Button(action: action) {
            layout {
                Image(systemName: symbol)
                    .glyphSize(Glyph.large)
                    .foregroundStyle(Palette.accent)
                    // One symbol height, so tiles side by side keep their labels on one line.
                    .frame(height: stacked ? nil : Glyph.large * Control.maxTextGrowth)
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(stacked ? .leading : .center)
                    .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, minHeight: stacked ? nil : ActionTile.minHeight)
            .background(prominent ? Palette.lit : Palette.chrome,
                        in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
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
                    ActionTile(title: "Import a File", symbol: Icons.importFile) {}
                }
            }
        }
    }
}

#Preview("ActionTile · light", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.light) }
#Preview("ActionTile · dark", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.dark) }
#Preview("ActionTile · AX5", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.largestText) }
#endif
