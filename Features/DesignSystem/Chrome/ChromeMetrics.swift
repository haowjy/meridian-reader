import CoreGraphics

/// The compact bottom chrome's sizes, from the approved mockups (`width-table.md`). Everything
/// that sets a size reads from here; `ChromeGeometry` places the pieces with them.
///
/// One shape language: every floating piece is a Capsule or a Circle, so its corner radius is
/// half its height, and a circle's diameter is its row's height. Three heights, no others:
///
/// ```
/// row 1   52   ‹ (circle) or ‹ › (capsule), the address field, the Library search
/// row 2   56   the pill, ▶ (circle), ⋯ (circle)
/// one row 48   every piece when collapsed or searching
/// ```
///
/// The pill's lit segment is a capsule inset by `litInset` on all four sides, so its radius is
/// the pill's radius minus the inset (concentric), as in Apple Music's and Reddit's tab capsules.
///
/// Every size is a multiple of `unit` except `bottomPadding` (6, today's). The smaller scale the
/// design recommends (D) is a one-edit switch: row1Height 11 * unit, row2Height 12 * unit,
/// collapsedHeight 11 * unit, bottomPadding 2 * unit, labelSize 10 (heights 44 / 48 / 44, footprint
/// 112, collapsed 56). `tools/check-tokens.js` in the design folder compares this file with the
/// mockups. The sizes both widths share are `BottomChrome`'s.
enum ChromeMetrics {
    /// The base unit every other size is a multiple of.
    static let unit: CGFloat = 4

    /// Left and right margin; also the gap between a row's pieces and the screen edge.
    static let margin: CGFloat = 3 * unit
    /// Gap between two pieces on a row, and between the rows.
    static let gap: CGFloat = 2 * unit
    /// The space above the top row and below the bottom row.
    static let topPadding: CGFloat = unit
    static let bottomPadding: CGFloat = 6

    /// Row 1 (expanded): the arrows, the address field, the Library search.
    static let row1Height: CGFloat = 13 * unit
    /// Row 2 (expanded): the pill, ▶, ⋯ and the edit bar.
    static let row2Height: CGFloat = 14 * unit
    /// The one row (collapsed or searching): every piece.
    static let collapsedHeight: CGFloat = 12 * unit
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = row1Height
    static let navPairWidth: CGFloat = 2 * row1Height

    /// The narrowest address field before the arrows give way to it.
    static let minimumField: CGFloat = 120
    /// The pill's lit segment is inset from the pill's edge and from its neighbours by this much,
    /// on all four sides.
    static let litInset = unit

    // Inside the pieces. Every glyph is `BottomChrome.iconSize`, medium weight.
    /// A pill segment's label, and the gap between it and its glyph.
    static let labelSize: CGFloat = 11
    static let segmentGap: CGFloat = 2
    /// The glyph's cell in a pill segment: the spinner takes the same room as the symbols.
    static let segmentGlyphHeight: CGFloat = 22
    /// The Reader segment while there is nothing to open.
    static let segmentDimmedOpacity = 0.55
    /// ▶'s progress ring: its line width and its inset from the circle.
    static let ringWidth: CGFloat = 2.5
    static let ringInset: CGFloat = 4
    /// The fade behind the chrome: page text dissolves over this height above the top piece and is
    /// fully covered from there down.
    static let fadeHeight: CGFloat = 28

    /// What the chrome reserves at the bottom of a scrolling screen (expanded), above the safe
    /// area: the same on every destination, so a screen never resizes when the chrome collapses.
    static let footprint: CGFloat = topPadding + row1Height + gap + row2Height + bottomPadding
    /// One row high: what a screen keeps clear while the chrome is collapsed or searching.
    static let collapsedFootprint: CGFloat = topPadding + collapsedHeight + bottomPadding
    /// Row 2 alone: what the Reader's text keeps clear, expanded or collapsed (the Reader has no row 1).
    static let row2Footprint: CGFloat = topPadding + row2Height + bottomPadding
}
