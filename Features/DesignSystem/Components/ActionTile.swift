import SwiftUI

/// A big square-ish tile that starts something: a large symbol over a short label, on a soft filled
/// surface. Laid out by `ActionTileGrid` where a screen offers a few clearly separate ways in, such
/// as every empty screen's (`AddToLibraryTiles`). `prominent` tints the surface with the accent for
/// the first choice; the rest sit on the neutral fill. It fills the height its row gives it, so
/// tiles side by side stay the same size when one label is taller.
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
            .frame(maxWidth: .infinity, minHeight: stacked ? nil : ActionTile.minHeight, maxHeight: .infinity)
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

/// `ActionTile`s two to a row, each row as tall as its tallest tile, then an optional `wide` tile
/// across the full width, last. At the accessibility sizes, where two side by side would break their
/// words, every tile takes a row of its own; `wide` stays last.
struct ActionTileGrid: View {
    let tiles: [ActionTile]
    var wide: ActionTile?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: tiles.count, by: perRow).map { Array(tiles[$0 ..< min($0 + perRow, tiles.count)]) }
        VStack(spacing: Spacing.s) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Spacing.s) {
                    ForEach(rows[index].indices, id: \.self) { rows[index][$0] }
                    // A short last row keeps its tile at a column's width.
                    if rows[index].count < perRow { Color.clear.frame(maxWidth: .infinity) }
                }
                // The row's height is its tallest tile's; the tiles (maxHeight: .infinity) fill it.
                .fixedSize(horizontal: false, vertical: true)
            }
            if let wide {
                wide.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
struct ActionTileGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("two to a row, one wide") {
                ActionTileGrid(tiles: [
                    ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {},
                    ActionTile(title: "Import a File", symbol: Icons.importFile) {},
                    ActionTile(title: "A Much Longer Label Here", symbol: Icons.paste) {},
                ], wide: ActionTile(title: "Add a Link", symbol: Icons.link) {})
            }
        }
    }
}

#Preview("ActionTile · light", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.light) }
#Preview("ActionTile · dark", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.dark) }
#Preview("ActionTile · AX5", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.largestText) }
#endif
