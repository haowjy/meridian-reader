import CoreGraphics

/// The compact bottom chrome's sizes. Names and values are the mockups' `SZ` (`chrome.js`);
/// `tools/check-tokens.js` in the design folder compares the two. Everything that sets a size
/// reads from here: `ChromeLayout` places the pieces with them, and no other file holds a bar size.
///
/// One shape language and one height: every floating piece is a Capsule or a Circle `barHeight`
/// (36 pt) high (the pill, the search and address fields, ‹ ›, ▶, ⋯, ✕, the keyboard's row), so its
/// corner radius is half that, and every one is tapped in `minTapTarget` (`hitOutset` past its edge).
/// The rows sit low: the bottom row ends `edgeClearance` above the screen's edge, in the home
/// indicator's strip. Scrolling down folds in steps: row 2 goes (the field drops to its place), then
/// the field goes into the domain strip (`stripHeight`), a line of text above the home indicator; a
/// tap on it brings both rows back. Changing `barHeight` changes every piece and every footprint.
///
/// Footprints are measured from the screen's bottom edge (the home indicator's strip included);
/// `aboveSafeArea` turns one into what a view laid out above the safe area keeps clear.
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
    /// The three-segment pill's width: one constant on every iPhone, never derived from the screen. With
    /// the gaps, ▶ and ⋯ it fits the SE's 375 pt with room to spare (`bottomRowWidth`, margin 12 each side).
    static let pillWidth: CGFloat = 235
    /// The bottom row's narrowest width: [pill] [▶ slot] [⋯] with one `rowGap` between (327; the SE's 375 less
    /// the margins is 351). The row runs margin to margin like the top row; on a wider screen the gap after the pill grows.
    static let bottomRowWidth: CGFloat = pillWidth + 2 * (rowGap + barHeight)
    /// Cancel's width while a search is editing: a word, not a circle. The keyboard's row is
    /// [field][Cancel] from margin to margin on every phone, the field taking what Cancel leaves.
    static let cancelWidth: CGFloat = 72
    /// The space above the top row.
    static let topPadding: CGFloat = unit
    /// From the bottom row's lower edge (and the strip's) to the screen's bottom edge: the rows use the
    /// home indicator's strip, as Brave's do. Not a multiple of the unit.
    static let edgeClearance: CGFloat = 14
    /// The home indicator's strip on a phone that has one; what `ChromeState.homeInset` assumes until
    /// the host has measured it.
    static let homeIndicatorStrip: CGFloat = 34

    /// The one height of every piece, in every row and state: thin, and still tapped in `minTapTarget`.
    static let barHeight: CGFloat = 9 * unit
    /// Listen's ‹ capsule at its widest: a long place name truncates before the middle of a phone.
    static let listenBackMaxWidth: CGFloat = 50 * unit
    /// Hit areas never go below this, whatever they look like.
    static let minTapTarget: CGFloat = 44
    /// How far a piece's hit area reaches past its glass on every side: 4 pt, so the rows' hit areas
    /// meet in the 8 pt gap between them and never overlap; neighbours on a row keep `rowGap - 2 * hitOutset` apart.
    static let hitOutset: CGFloat = (minTapTarget - barHeight) / 2
    /// The glyph slot at each end of a capsule, and its inset from the capsule's end, top and bottom
    /// (concentric: the slot's corners follow the end cap's, `barHeight / 2 - endInset`).
    static let endGlyphSlot: CGFloat = 6 * unit
    static let endInset: CGFloat = (barHeight - endGlyphSlot) / 2
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = barHeight
    static let navPairWidth: CGFloat = 2 * barHeight

    /// The pill's lit segment is inset from the pill's edge and from its neighbours by this much.
    static let litInset = unit

    // Inside the pieces: one glyph size everywhere. The tabs are glyphs only (their names are for
    // VoiceOver and the large content viewer).
    /// A control's glyph, and the glyph's cell in a pill segment.
    static let segmentGlyphHeight: CGFloat = 20
    /// The Reader segment while there is nothing to open.
    static let segmentDimmedOpacity = 0.55
    /// ▶'s progress ring: its line width and its inset from the circle.
    static let ringWidth: CGFloat = 2.5
    static let ringInset: CGFloat = 4

    // MARK: - The strip (the folded chrome)

    /// What both rows fold into once a scroll down has taken them: the page's name (a domain, a title)
    /// in one line of text just above the home indicator, no glass (Brave's). A tap on it brings the
    /// rows back. Its box is `stripHeight` tall, its lower edge `edgeClearance` above the screen's edge.
    static let stripHeight: CGFloat = 5 * unit
    /// Fixed like every glyph and label here: it never grows with text size (a long press shows it large).
    static let stripFontSize: CGFloat = 13
    /// Between the strip's text and the end of its hit area, each side.
    static let stripSidePadding: CGFloat = 10
    /// The longest the text runs; longer is cut with an ellipsis.
    static let stripMaxWidth: CGFloat = 260
    /// How far the hit area reaches past the strip above and below: `minTapTarget` tall.
    static let stripHitOutset: CGFloat = (minTapTarget - stripHeight) / 2

    /// The strip's width for text `textWidth` wide: the text and its side padding, at most `stripMaxWidth`.
    static func stripWidth(forTextWidth textWidth: CGFloat) -> CGFloat {
        min(stripMaxWidth, max(stripHeight, textWidth + 2 * stripSidePadding))
    }

    /// How far above the top piece the fade behind the chrome starts.
    static let fadeRise: CGFloat = 50

    /// The Reader's player card above row 2 (Listen's card is not resized with the bars: its own height
    /// and corner radius).
    static let card: CGFloat = 140
    static let cardRadius: CGFloat = 6 * unit

    /// What the chrome covers at the bottom of a scrolling screen, from the screen's edge: two rows,
    /// the same on every destination, so a screen never resizes when the chrome folds (98 pt).
    static let footprint: CGFloat = topPadding + barHeight + gap + barHeight + edgeClearance
    /// One row: the keyboard's form, and the fold's first step (54 pt).
    static let collapsedFootprint: CGFloat = topPadding + barHeight + edgeClearance
    /// The fold's end: the strip (38 pt).
    static let stripFootprint: CGFloat = topPadding + stripHeight + edgeClearance
    /// What the Reader's text keeps clear: the card, a gap and row 2.
    static let readerFootprint: CGFloat = topPadding + card + gap + barHeight + edgeClearance
    /// What the chrome covers at a fold step (`ChromeScroll.drawnStep`): 0 two rows, 1 one row, 2 the strip.
    static func footprint(step: Int) -> CGFloat {
        step <= 0 ? footprint : step == 1 ? collapsedFootprint : stripFootprint
    }

    /// A footprint (from the screen's edge) as what a view laid out above a safe area `home` deep keeps clear.
    static func aboveSafeArea(_ footprint: CGFloat, home: CGFloat) -> CGFloat { max(0, footprint - home) }

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
