import CoreGraphics

/// The compact bottom chrome's sizes. Names and values are the mockups' `SZ` (`chrome.js`);
/// `tools/check-tokens.js` in the design folder compares the two. Everything that sets a size
/// reads from here: `ChromeLayout` places the pieces with them, and no other file holds a bar size.
///
/// One shape language and one height: every floating piece is a Capsule or a Circle `barHeight`
/// high (the pill, the search and address fields, ‹ ›, ▶, ⋯, ✕, the screen icon, the collapsed
/// row), so its corner radius is half that. Collapsing changes the row count, never a piece's size.
/// Changing `barHeight` changes every piece and every footprint.
///
/// The pill's lit segment is a capsule inset by `litInset` on all four sides, so it is
/// `barHeight - 2 * litInset` tall and its radius is the pill's minus the inset (concentric).
enum ChromeMetrics {
    /// The base unit every other size is a multiple of.
    static let unit: CGFloat = 4

    /// Left and right margin; also the gap between a row's pieces and the screen edge.
    static let margin: CGFloat = 3 * unit
    /// Gap between two pieces on a row, and between the rows.
    static let gap: CGFloat = 2 * unit
    /// The space above the top row and below the bottom row.
    static let topPadding: CGFloat = unit
    static let bottomPadding: CGFloat = 2 * unit

    /// The one height of every piece, in every row and state.
    static let barHeight: CGFloat = 12 * unit
    /// Hit areas never go below this, whatever they look like.
    static let minTapTarget: CGFloat = 44
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = barHeight
    static let navPairWidth: CGFloat = 2 * barHeight

    /// The narrowest address or search field before the arrows give way to it.
    static let minimumField: CGFloat = 120
    /// The pill's lit segment is inset from the pill's edge and from its neighbours by this much.
    static let litInset = unit

    // Inside the pieces: one glyph size and one label size everywhere.
    /// A control's glyph, and the glyph's cell in a pill segment.
    static let segmentGlyphHeight: CGFloat = 22
    static let labelSize: CGFloat = 11
    /// The gap between a segment's glyph and its label.
    static let segmentGap: CGFloat = 2
    /// The Reader segment while there is nothing to open.
    static let segmentDimmedOpacity = 0.55
    /// ▶'s progress ring: its line width and its inset from the circle.
    static let ringWidth: CGFloat = 2.5
    static let ringInset: CGFloat = 4

    /// How far above the top piece the fade behind the chrome starts.
    static let fadeRise: CGFloat = 50

    /// The Reader's player card above row 2.
    static let card: CGFloat = 152

    /// What the chrome reserves at the bottom of a scrolling screen, above the safe area: two
    /// rows, the same on every destination, so a screen never resizes when the chrome collapses.
    static let footprint: CGFloat = topPadding + barHeight + gap + barHeight + bottomPadding
    /// One row high: the collapsed chrome and the keyboard's.
    static let collapsedFootprint: CGFloat = topPadding + barHeight + bottomPadding
    /// What the Reader's text keeps clear: the card, a gap and row 2.
    static let readerFootprint: CGFloat = topPadding + card + gap + barHeight + bottomPadding

    // MARK: - Fields

    /// An address field in the chrome shows its reader-mode icon from `readerIconWidth.lowerBound`
    /// wide, in full at `upperBound`, and reload from `reloadWidth`: they ease in as the field
    /// widens and out as it narrows, never by a separate state (the mockups' `rectsFor`).
    static let readerIconWidth: ClosedRange<CGFloat> = 150...180
    static let reloadWidth: ClosedRange<CGFloat> = 200...230

    /// 0 up to `range.lowerBound`, 1 from `range.upperBound`, a straight line between.
    static func ramp(_ t: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
}
