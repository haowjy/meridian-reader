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
/// The column is `Glyph.slot` wide. The row's minimum is `rowMinimum`: `Control.bar` on a card list
/// (`cardListStyle`, the one card-row policy), `Control.tap` elsewhere (the ⋯ panel, the search
/// suggestions); both grow with the text up to `Control.maxTextGrowth`. Without a leading view (`symbol` nil)
/// the text starts at the row's edge: a card's rows either all lead with a symbol or none does.
/// The row adds no horizontal padding (its list or panel has its own) and no tap: the caller
/// wraps it in a `Button`, `NavigationLink` or `Toggle`. On the reading page it takes the
/// theme's ink.
struct SymbolRow<Leading: View, Trailing: View>: View {
    let title: String
    /// Line two (a `DetailLine` part).
    var subtitle: DetailPart?
    /// The title's and the symbol's colour (nil: ink): the accent for *New Folder*, red for
    /// *Unfollow*.
    var ink: Color?
    let leading: Leading?
    @ViewBuilder let trailing: Trailing

    @Environment(\.readingPalette) private var reading
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.rowMinimum) private var minimum
    @ScaledMetric(relativeTo: .body) private var scaledColumn = Glyph.slot
    /// How much the row type has grown (1 at the default size).
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var growth: CGFloat = 1

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let leading {
                leading
                    .glyphSize(Glyph.regular)
                    .frame(width: Control.grown(scaledColumn, from: Glyph.slot))
                    .accessibilityHidden(true)
            }
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .typeStyle(.row)
                        // Whole labels at Accessibility sizes (C130): two lines there, one otherwise.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    if let subtitle {
                        DetailLine(parts: [subtitle])
                            .typeStyle(.caption)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                trailing
            }
            // Clear of the separators when two lines outgrow the minimum: a card adds no inset
            // of its own (`listCard`).
            .padding(.vertical, Spacing.xs)
            // The separator under the row starts at the title, as in every list.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .foregroundStyle(ink ?? reading?.ink ?? Palette.ink)
        .frame(minHeight: Control.grown(minimum * growth, from: minimum))
        .contentShape(Rectangle())
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

    @ScaledMetric(relativeTo: .body) private var scaledColumn = Glyph.slot

    var body: some View {
        Divider()
            .padding(.leading, leadingInset + Control.grown(scaledColumn, from: Glyph.slot) + Spacing.s)
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
