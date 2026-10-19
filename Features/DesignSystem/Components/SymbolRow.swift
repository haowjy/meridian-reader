import SwiftUI

/// The compact row: a symbol (or a small site tile) in one leading column, a title on one line
/// and an optional subtitle under it, then the caller's trailing view. Settings, the ⋯ panel,
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
/// The column is `Glyph.rowLeading` wide and the row at least `RowHeight.compact` tall
/// (`RowHeight.menu` in the ⋯ panel); both grow with the text up to `BottomChrome.maxTextGrowth`. Without a leading view (`symbol` nil)
/// the text starts at the row's edge: a card's rows either all lead with a symbol or none does.
/// The row adds no horizontal padding (its list or panel has its own) and no tap: the caller
/// wraps it in a `Button`, `NavigationLink` or `Toggle`. On the reading page it takes the
/// theme's ink.
struct SymbolRow<Leading: View, Trailing: View>: View {
    let title: String
    /// Line two (a `DetailLine` part, so a downloaded model's starts with the grey ✓).
    var subtitle: DetailPart?
    /// The title's and the symbol's colour (nil: ink): the accent for *New Folder*, red for
    /// *Unfollow*.
    var ink: Color?
    let leading: Leading?
    @ViewBuilder let trailing: Trailing
    /// The row's height at the default text size: `RowHeight.compact`, or `.menu` in the ⋯ panel.
    var height: CGFloat = RowHeight.compact

    @Environment(\.readingPalette) private var reading
    @ScaledMetric(relativeTo: .body) private var scaledColumn = Glyph.rowLeading
    /// How much the row type has grown (1 at the default size).
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var growth: CGFloat = 1

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let leading {
                leading
                    .rowSymbol()
                    .frame(width: BottomChrome.grown(scaledColumn, from: Glyph.rowLeading))
                    .accessibilityHidden(true)
            }
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row)
                        .lineLimit(1)
                    if let subtitle {
                        DetailLine(parts: [subtitle])
                            .typeStyle(.caption)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                trailing
            }
            .padding(.vertical, Spacing.xxs)
            // The separator under the row starts at the title, as in every list.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .foregroundStyle(ink ?? reading?.ink ?? Palette.ink)
        .frame(minHeight: BottomChrome.grown(height * growth, from: height))
        .contentShape(Rectangle())
    }
}

extension SymbolRow {
    /// The row `height` tall at the default text size (`RowHeight.menu` in the ⋯ panel).
    func rowHeight(_ height: CGFloat) -> Self {
        var row = self
        row.height = height
        return row
    }
}

extension SymbolRow where Leading == Image {
    /// A row led by an SF Symbol (nil: no leading column).
    init(_ title: String, subtitle: DetailPart? = nil, symbol: String?, ink: Color? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, ink: ink, leading: symbol.map { Image(systemName: $0) },
                  trailing: trailing)
    }
}

extension SymbolRow where Leading == Image, Trailing == EmptyView {
    init(_ title: String, subtitle: DetailPart? = nil, symbol: String?, ink: Color? = nil) {
        self.init(title, subtitle: subtitle, symbol: symbol, ink: ink) { EmptyView() }
    }
}

extension SymbolRow {
    /// A row led by any view of the column's size (a site tile).
    init(_ title: String, subtitle: DetailPart? = nil, ink: Color? = nil, @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, ink: ink, leading: leading(), trailing: trailing)
    }
}

/// The line between `SymbolRow`s stacked outside a `List` (the search layer): from the title's
/// leading edge, after a row inset by `leadingInset`.
struct SymbolRowSeparator: View {
    var leadingInset: CGFloat = 0

    @ScaledMetric(relativeTo: .body) private var scaledColumn = Glyph.rowLeading

    var body: some View {
        Divider()
            .padding(.leading, leadingInset + BottomChrome.grown(scaledColumn, from: Glyph.rowLeading) + Spacing.s)
    }
}

#if DEBUG
struct SymbolRowGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("a setting, a link, a switch") {
                VStack(spacing: 0) {
                    SymbolRow("Listening Audio", symbol: Icons.storage) { Text("12 MB").typeStyle(.row) }
                    SymbolRow("Language", symbol: Icons.browser) {
                        Text("Automatic").typeStyle(.row).foregroundStyle(Palette.secondaryInk)
                        Image(systemName: Icons.disclosure).disclosureSymbol().foregroundStyle(Palette.secondaryInk)
                    }
                    Toggle(isOn: .constant(true)) { SymbolRow("Block Ads", symbol: Icons.blockAds) }
                }
            }
            PreviewState("with a subtitle, no symbol") {
                SymbolRow("Kokoro (on-device)", subtitle: "Recommended, ~175 MB download", symbol: nil)
            }
            PreviewState("a site tile, an accent action") {
                SymbolRow("Notes on Tides", subtitle: "example.org") {
                    ArtworkTile(letter: "example.org", size: Glyph.rowLeading)
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
