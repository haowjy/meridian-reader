import SwiftUI

/// A tile in a two-column action grid. At accessibility sizes each takes a row.
struct ActionTile: View {
    let title: String
    let symbol: String
    var prominent = false
    var identifier: String?
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The symbol's slot over a cell's label: its size, grown with the text as the symbol is.
    @ScaledMetric(relativeTo: .body) private var symbolLine = Glyph.large

    var body: some View {
        // At the accessibility sizes tiles stack, one to a row, each laid out as a row (symbol before
        // its label), so a screen's tiles and its heading need as little height as they can.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(HStackLayout(spacing: Spacing.s)) : AnyLayout(VStackLayout(spacing: Spacing.xs))
        Button(action: action) {
            layout {
                Image(systemName: symbol)
                    .glyphSize(Glyph.large)
                    .foregroundStyle(Palette.accent)
                    // One symbol height in a cell, so tiles side by side keep their labels on one line.
                    .frame(height: stacked ? nil : Control.grown(symbolLine, from: Glyph.large))
                Text(title)
                    .typeStyle(.row, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(stacked ? .leading : .center)
                    .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, stacked ? Spacing.xs : Spacing.m)
            .frame(maxWidth: .infinity, minHeight: stacked ? RowMetrics.oneLineHeight : nil, maxHeight: .infinity)
            .background(prominent ? Palette.lit : Palette.chrome,
                        in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Two equal columns, or one at accessibility sizes so labels stay readable.
struct ActionTileGrid: View {
    let tiles: [ActionTile]

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
        }
    }
}

#if DEBUG
struct ActionTileGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("four tiles") {
                ActionTileGrid(tiles: [
                    ActionTile(title: "Browse the Web", symbol: Icons.browser, prominent: true) {},
                    ActionTile(title: "Add a Link", symbol: Icons.link) {},
                    ActionTile(title: "Import a File", symbol: Icons.importFile) {},
                    ActionTile(title: "Paste Text", symbol: Icons.paste) {},
                ])
            }
        }
    }
}

#Preview("ActionTile · light", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.light) }
#Preview("ActionTile · dark", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.dark) }
#Preview("ActionTile · AX5", traits: .sizeThatFitsLayout) { ActionTileGallery().previewVariant(.largestText) }
#endif
