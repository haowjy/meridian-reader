import SwiftUI

/// The one geometry of a list row: every card row (`ListRow`, `SymbolRow`, `VoiceRow`, Follow's
/// chapters) takes its height, insets, leading column and trailing accessory from here, so rows of
/// one kind are one height at a given text size and line up across screens.
///
/// ```
/// │←16→[col]←12→Title                                [ ⋯ ]│   one line: `oneLineHeight` (48)
/// │          Detail                              ←16→│      two lines: `twoLineHeight`, both lines + 2 × 8
///                                         slot 44, its glyph ending 16 in
/// ```
///
/// - Height: a row reserves its lines whatever it shows now (a detail that comes and goes keeps
///   its line), so a row never changes height. One line is `Control.bar` (`rowMinimum` off a card
///   list), growing with the text up to `Control.maxTextGrowth`; two lines are the title's and the
///   detail's line heights, scaled with the text, plus `verticalInset` above and below. Larger text
///   grows a row through its content; at the accessibility sizes a title may wrap.
/// - Leading: content starts `edgeInset` in from the card; a leading column (a symbol, a checkbox) is
///   `symbolColumn` wide, `columnGap` before the text. A page's thumbnail column is its two lines' height
///   (`ListRow`), a voice's ▶ its tap square (`VoiceRow`).
/// - Trailing: text and marks end `edgeInset` in; a trailing control is `Control.tap` square
///   (`accessorySlot`), `accessoryTrailing` from the card's edge so its `Glyph.regular` glyph also ends
///   `edgeInset` in. (The top bar's ⋯ is centred 18 in from the card's edge,
///   `Spacing.topBarMargin` + half `Control.chrome` less the page margin: a 44 pt slot there would
///   cross the card's edge, so rows line up with the card's text instead.)
enum RowMetrics {
    /// Above and below a row's text.
    static let verticalInset = Spacing.xs
    /// From the card's leading and trailing edges to the row's content.
    static let edgeInset = Spacing.m
    /// Between a leading column and the text.
    static let columnGap = Spacing.s
    /// A leading symbol's or checkbox's column.
    static let symbolColumn = Glyph.slot
    /// A one-line row at the default text size, on a card list: the list's row minimum (`cardListStyle`).
    static let oneLineHeight = Control.bar
    /// A trailing control's square.
    static let accessorySlot = Control.tap
    /// From the card's trailing edge to a trailing control's square: its glyph then ends `edgeInset` in.
    static let accessoryTrailing = edgeInset - (accessorySlot - Glyph.regular) / 2
    /// A title beside other content: one line, two at the accessibility sizes (whole labels).
    static func titleLines(_ size: DynamicTypeSize) -> Int { size.isAccessibilitySize ? 2 : 1 }
    /// A title on a line of its own above the rest (`ListRow` at the accessibility sizes).
    static let stackedTitleLines = 3

    /// A two-line row: its title's and detail's line heights (each scaled with the text) and the
    /// vertical inset above and below.
    static func twoLineHeight(title: CGFloat, detail: CGFloat) -> CGFloat {
        title + detail + 2 * verticalInset
    }
}

extension View {
    /// A trailing control's square (`RowMetrics.accessorySlot`), its tap reaching into the row's vertical
    /// inset rather than making the row taller: a row is as tall as its lines, whatever control ends it.
    func rowAccessorySlot() -> some View {
        frame(width: RowMetrics.accessorySlot, height: RowMetrics.accessorySlot)
            .padding(.vertical, -RowMetrics.verticalInset)
    }

    /// A row's height for `lines` lines of text (1 or 2) and its vertical inset (`RowMetrics`).
    func rowHeight(lines: Int) -> some View {
        modifier(RowHeight(lines: lines))
    }
}

private struct RowHeight: ViewModifier {
    let lines: Int

    @Environment(\.rowMinimum) private var minimum
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var titleLine = TypeStyle.row.lineHeight
    @ScaledMetric(relativeTo: TypeStyle.caption.relativeTo) private var detailLine = TypeStyle.caption.lineHeight
    /// How much the row type has grown (1 at the default size).
    @ScaledMetric(relativeTo: TypeStyle.row.relativeTo) private var growth: CGFloat = 1

    private var height: CGFloat {
        lines <= 1 ? Control.grown(minimum * growth, from: minimum)
            : RowMetrics.twoLineHeight(title: titleLine, detail: detailLine)
    }

    func body(content: Content) -> some View {
        content
            .padding(.vertical, RowMetrics.verticalInset)
            .frame(minHeight: height)
    }
}

/// A row's columns: the leading column (`RowMetrics.symbolColumn`, growing with the text), the gap,
/// then the rest, whose leading edge the separator starts at. No height, padding or tap of its own:
/// `SymbolRow` draws its text in it, and a row with two taps (Follow's checkbox and its chapter) puts a
/// button in each.
struct RowColumns<Leading: View, Content: View>: View {
    let leading: Leading?
    /// The leading column is a control of its own (Follow's checkbox), for VoiceOver too; otherwise
    /// it only illustrates the text and VoiceOver skips it.
    var leadingIsControl = false
    @ViewBuilder let content: Content

    @ScaledMetric(relativeTo: .body) private var scaledColumn = RowMetrics.symbolColumn

    var body: some View {
        HStack(spacing: RowMetrics.columnGap) {
            if let leading {
                leading
                    .glyphSize(Glyph.regular)
                    .frame(width: Control.grown(scaledColumn, from: RowMetrics.symbolColumn))
                    .accessibilityHidden(!leadingIsControl)
            }
            content
                // The separator under the row starts at the text, as in every list.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
    }
}
