import CoreGraphics

/// The compact bottom chrome's sizes. Names and values are the mockups' `SZ` (`chrome.js`);
/// `tools/check-tokens.js` in the design folder compares the two. Everything that sets a size
/// reads from here: `ChromeLayout` places the pieces with them, and no other file holds a bar size.
///
/// One shape language and one height: every floating piece is a Capsule or a Circle `barHeight`
/// high (the pill, the search and address fields, ‹ ›, ▶, ⋯, ✕, the keyboard's row), so its corner
/// radius is half that. Scrolling down folds both rows into one small capsule (`capsuleHeight`)
/// that names the page; a tap on it brings the rows back. Changing `barHeight` changes every piece
/// and every footprint.
///
/// The pill's lit segment is a capsule inset by `litInset` on all four sides, so it is
/// `barHeight - 2 * litInset` tall and its radius is the pill's minus the inset (concentric).
enum ChromeMetrics {
    /// The base unit every other size is a multiple of.
    static let unit: CGFloat = 4

    /// Left and right margin; also the gap between a row's pieces and the screen edge.
    static let margin: CGFloat = 3 * unit
    /// Gap between the rows (and the card over row 2).
    static let gap: CGFloat = 2 * unit
    /// Gap between two pieces on one row: [pill] [▶] [⋯], [content] [icon] [▶] [⋯], ‹ › and the field.
    /// About a quarter of the bar's height, the same between every pair. The one size here that is not
    /// a multiple of the unit.
    static let rowGap: CGFloat = 10
    /// The three-segment pill's width: one constant on every iPhone, never derived from the screen. It is
    /// the iPhone SE's: with the gaps, ▶ and ⋯ it fills the SE's 375 pt exactly (`bottomRowWidth`, margin 12 each side).
    static let pillWidth: CGFloat = 235
    /// The bottom row's whole width: [pill] [▶ slot] [⋯] with one `rowGap` between. Fixed (351). On a wider
    /// phone the row keeps this size and is centred, so the space either side is equal; it is never stretched.
    static let bottomRowWidth: CGFloat = pillWidth + 2 * (rowGap + barHeight)
    /// Cancel's width while a search is editing: a word, not a circle. The keyboard's row is
    /// [field][Cancel] from margin to margin on every phone, the field taking what Cancel leaves.
    static let cancelWidth: CGFloat = 72
    /// The space above the top row and below the bottom row.
    static let topPadding: CGFloat = unit
    static let bottomPadding: CGFloat = 2 * unit

    /// The one height of every piece, in every row and state.
    static let barHeight: CGFloat = 12 * unit
    /// Listen's ‹ capsule at its widest: a long place name truncates before the middle of a phone.
    static let listenBackMaxWidth: CGFloat = 50 * unit
    /// Hit areas never go below this, whatever they look like.
    static let minTapTarget: CGFloat = 44
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = barHeight
    static let navPairWidth: CGFloat = 2 * barHeight

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

    // MARK: - The capsule (the folded chrome)

    /// The capsule that stands for both rows once a scroll down has folded them: it names the page (a
    /// domain, a title) and a tap on it brings the rows back. Bottom-aligned with row 2.
    static let capsuleHeight: CGFloat = 7 * unit
    /// Fixed like every glyph and label here: it never grows with text size (a long press shows it large).
    static let capsuleFontSize: CGFloat = 12
    /// Between the capsule's edge and its text, each side.
    static let capsuleSidePadding: CGFloat = 10
    /// What the folded chrome reserves at the bottom of the web page: padding, the capsule and the bottom padding.
    static let capsuleFootprint: CGFloat = topPadding + capsuleHeight + bottomPadding
    /// The longest it grows; a longer title is cut with an ellipsis.
    static let capsuleMaxWidth: CGFloat = 240
    /// How far the hit area reaches past the capsule on every side: `minTapTarget` tall, wider than
    /// the capsule by the same amount each side.
    static let capsuleHitOutset: CGFloat = (minTapTarget - capsuleHeight) / 2

    /// The capsule's width for text `textWidth` wide: the text and its side padding, at least a
    /// circle and at most `capsuleMaxWidth`.
    static func capsuleWidth(forTextWidth textWidth: CGFloat) -> CGFloat {
        min(capsuleMaxWidth, max(capsuleHeight, textWidth + 2 * capsuleSidePadding))
    }

    /// How far above the top piece the fade behind the chrome starts.
    static let fadeRise: CGFloat = 50

    /// The Reader's player card above row 2.
    static let card: CGFloat = 140

    /// What the chrome reserves at the bottom of a scrolling screen, above the safe area: two
    /// rows, the same on every destination, so a screen never resizes when the chrome collapses.
    static let footprint: CGFloat = topPadding + barHeight + gap + barHeight + bottomPadding
    /// One row high: the keyboard's form (a search is editing).
    static let collapsedFootprint: CGFloat = topPadding + barHeight + bottomPadding
    /// What the Reader's text keeps clear: the card, a gap and row 2.
    static let readerFootprint: CGFloat = topPadding + card + gap + barHeight + bottomPadding

    // MARK: - Fields

    /// An address field in the chrome shows its reader-mode icon from `readerIconWidth.lowerBound`
    /// wide, in full at `upperBound` (the 🔍 hint too; ↻ never gives way): it eases in as the field
    /// widens and out as it narrows, never by a separate state (the mockups' `rectsFor`).
    static let readerIconWidth: ClosedRange<CGFloat> = 150...180

    /// 0 up to `range.lowerBound`, 1 from `range.upperBound`, a straight line between.
    static func ramp(_ t: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        min(1, max(0, (t - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
}
