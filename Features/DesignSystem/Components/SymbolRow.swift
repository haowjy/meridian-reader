import SwiftUI

/// The compact row: a symbol (or a small site tile) in one leading column, a title on one line
/// and an optional subtitle under it, then the caller's trailing view. Settings, the ⋯ menu,
/// the Move tree, the search suggestions and Following's actions are all this row; the Library's
/// pages and folders are `ListRow`.
///
/// ```
/// 🌐  Language                       Automatic ›     a Settings link
/// 🔍  tide tables                             ↖︎     a recent search
/// ▣   Notes on Tides                          ↖︎     a suggestion: its site tile, two lines
///     example.org
/// ```
///
/// Its geometry is `RowMetrics`: the leading column (`RowColumns`), a one- or two-line height
/// (`rowHeight(lines:)`; `reservesDetail` keeps line two's room while it has nothing to say, so the
/// row never changes height), the title's lines. `rowMinimum` is a one-line row's height:
/// `Control.bar` on a card list (`cardListStyle`), `Control.tap` elsewhere (the ⋯ menu, the search
/// suggestions). Without a leading view (`symbol` nil) the text starts at the row's edge: a card's
/// rows either all lead with a symbol or none does. The row adds no horizontal padding (its list or
/// panel has its own) and no tap: the caller wraps it in a `Button`, `NavigationLink` or `Toggle`.
/// On the reading page it takes the theme's ink.
struct SymbolRow<Leading: View, Trailing: View>: View {
    let title: String
    /// Line two: its parts, set apart by space (`DetailLine`), never joined with a separator.
    var details: [DetailPart] = []
    /// Line two's room is kept while `details` is empty (a row whose second line comes and goes).
    var reservesDetail = false
    /// The title's and the symbol's colour (nil: ink): the accent for *New Folder*, red for
    /// *Unfollow*.
    var ink: Color?
    let leading: Leading?
    @ViewBuilder let trailing: Trailing

    @Environment(\.readingPalette) private var reading
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RowColumns(leading: leading) {
            HStack(spacing: RowMetrics.columnGap) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row)
                        .lineLimit(RowMetrics.titleLines(dynamicTypeSize))
                    if !details.isEmpty {
                        DetailLine(parts: details)
                            .typeStyle(.caption)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                trailing
            }
        }
        .foregroundStyle(ink ?? reading?.ink ?? Palette.ink)
        .rowHeight(lines: details.isEmpty && !reservesDetail ? 1 : 2)
        .contentShape(Rectangle())
    }
}

extension SymbolRow where Leading == Image {
    /// A row led by an SF Symbol (nil: no leading column).
    init(_ title: String, subtitle: DetailPart? = nil, reservesDetail: Bool = false, symbol: String?, ink: Color? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title, details: subtitle.map { [$0] } ?? [], reservesDetail: reservesDetail, symbol: symbol, ink: ink,
                  trailing: trailing)
    }

    /// A row whose second line has several parts ("Apache-2.0   Runs Kokoro’s voices").
    init(_ title: String, details: [DetailPart], reservesDetail: Bool = false, symbol: String?, ink: Color? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, details: details, reservesDetail: reservesDetail, ink: ink, leading: symbol.map { Image(systemName: $0) },
                  trailing: trailing)
    }
}

extension SymbolRow where Leading == Image, Trailing == EmptyView {
    init(_ title: String, subtitle: DetailPart? = nil, reservesDetail: Bool = false, symbol: String?, ink: Color? = nil) {
        self.init(title, subtitle: subtitle, reservesDetail: reservesDetail, symbol: symbol, ink: ink) { EmptyView() }
    }
}

extension SymbolRow {
    /// A row led by any view of the column's size (a site tile).
    init(_ title: String, subtitle: DetailPart? = nil, ink: Color? = nil, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, details: subtitle.map { [$0] } ?? [], ink: ink, leading: leading(), trailing: trailing)
    }
}

/// The line between `SymbolRow`s stacked outside a `List` (the search layer): from the title's
/// leading edge, after a row inset by `leadingInset`.
struct SymbolRowSeparator: View {
    var leadingInset: CGFloat = 0

    @ScaledMetric(relativeTo: .body) private var scaledColumn = RowMetrics.symbolColumn

    var body: some View {
        Divider()
            .padding(.leading, leadingInset + Control.grown(scaledColumn, from: RowMetrics.symbolColumn) + RowMetrics.columnGap)
    }
}

#if DEBUG
struct SymbolRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("a setting, a link, a switch") {
                VStack(spacing: 0) {
                    SymbolRow("Prepared Audio", symbol: Icons.preparedAudio) { Text("12").typeStyle(.row) }
                    SymbolRow("Language", symbol: Icons.browser) {
                        Text("Automatic").typeStyle(.row).foregroundStyle(Palette.secondaryInk)
                        Image(systemName: Icons.disclosure).disclosureSymbol().foregroundStyle(Palette.secondaryInk)
                    }
                    Toggle(isOn: .constant(true)) { SymbolRow("Search Suggestions", symbol: Icons.search) }
                }
            }
            PreviewState("with a subtitle, no symbol") {
                SymbolRow("Kokoro", subtitle: "About 175 MB to download", symbol: nil)
            }
            PreviewState("a site tile, an accent action") {
                SymbolRow("Notes on Tides", subtitle: "example.org") {
                    ArtworkTile(letter: "example.org", size: Glyph.slot)
                } trailing: { EmptyView() }
                SymbolRow("New Folder", symbol: Icons.newFolder, ink: Palette.accent)
            }
        }
    }
}

#Preview("SymbolRow · light", traits: .sizeThatFitsLayout) { SymbolRowGallery().previewVariant(.light) }
#Preview("SymbolRow · dark", traits: .sizeThatFitsLayout) { SymbolRowGallery().previewVariant(.dark) }
#Preview("SymbolRow · AX5", traits: .sizeThatFitsLayout) { SymbolRowGallery().previewVariant(.largestText) }
#endif
