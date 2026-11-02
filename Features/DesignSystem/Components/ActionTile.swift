import SwiftUI

/// A tile that starts something, on a soft filled surface. Laid out by `ActionTileGrid` where a screen
/// offers a few clearly separate ways in, such as every empty screen's (`AddToLibraryTiles`). In the
/// grid's two-to-a-row cells it is a symbol over a short label, as tall as they need. As the grid's
/// full-width tile (`actionTileRow`) it is a row, the symbol (`Glyph.regular`) beside the label, a
/// one-line row's height (`RowMetrics.oneLineHeight`); at the accessibility sizes every tile is such a
/// row. `prominent` tints the surface with the accent for the first choice; the rest sit on the neutral
/// fill. A cell fills the height its row gives it, so tiles side by side stay the same size when one
/// label is taller.
struct ActionTile: View {
    let title: String
    let symbol: String
    var prominent = false
    var identifier: String?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.actionTileRow) private var isWide
    /// The symbol's slot over a cell's label: its size, grown with the text as the symbol is.
    @ScaledMetric(relativeTo: .body) private var symbolLine = Glyph.large

    var body: some View {
        // At the accessibility sizes tiles stack, one to a row, each a row like the full-width one, so a
        // screen's tiles and its heading need as little height as they can.
        let stacked = typeSize.isAccessibilitySize
        let row = isWide || stacked
        let layout = row ? AnyLayout(HStackLayout(spacing: Spacing.s)) : AnyLayout(VStackLayout(spacing: Spacing.xs))
        Button(action: action) {
            layout {
                Image(systemName: symbol)
                    .glyphSize(isWide && !stacked ? Glyph.regular : Glyph.large)
                    .foregroundStyle(Palette.accent)
                    // One symbol height in a cell, so tiles side by side keep their labels on one line.
                    .frame(height: row ? nil : Control.grown(symbolLine, from: Glyph.large))
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(stacked ? .leading : .center)
                    .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, row ? Spacing.xs : Spacing.m)
            .frame(maxWidth: .infinity, minHeight: row ? RowMetrics.oneLineHeight : nil, maxHeight: .infinity)
            .background(prominent ? Palette.lit : Palette.chrome,
                        in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

extension EnvironmentValues {
    /// An `ActionTile` laid out as a row, symbol beside label: `ActionTileGrid`'s full-width tile.
    @Entry var actionTileRow = false
}

/// `ActionTile`s two to a row, each row as tall as its tallest tile, then an optional `wide` tile
/// across the full width, last, a row with its symbol beside its label. At the accessibility sizes, where two side by side would break their
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
                wide.environment(\.actionTileRow, true)
                    .fixedSize(horizontal: false, vertical: true)
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
