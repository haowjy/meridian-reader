import CoreGraphics

/// The compact bottom chrome's sizes. Names and values are the mockups' `SZ` (`chrome.js`);
/// `tools/check-tokens.js` in the design folder compares the two. Everything that sets a size
/// reads from here: `ChromeLayout` places the pieces with them, and no other file holds a bar size.
///
/// One shape language and one height: every floating piece is a Capsule or a Circle `barHeight`
/// (48 pt, Safari's) high (the pill, the search and address fields, ‹ ›, Listen, ⋯, ✕, the keyboard's row), so its
/// corner radius is half that, and every one is at least `minTapTarget` to tap.
/// The bottom row ends `edgeClearance` above the screen's edge, on the home indicator's strip as
/// Safari's does. Scrolling down folds in steps: row 2 goes (the field drops to its place), then
/// the field shrinks into the bubble (`bubbleHeight`), a small glass capsule naming the page just above
/// the home indicator; a tap on it, or a scroll up, brings both rows back. Changing `barHeight` changes every piece and every footprint.
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
    /// Gap between the rows.
    static let gap: CGFloat = 2 * unit
    /// Gap between two pieces on one row: ‹ › and the field, the field and Listen, the pill and ⋯, the
    /// keyboard's field and Cancel. Safari's (measured on an iPhone 17 Pro, iOS 26), the same between every pair.
    static let rowGap: CGFloat = 2 * unit
    /// Cancel's width while a search is editing: a word, not a circle. The keyboard's row is
    /// [field][Cancel] from margin to margin on every phone, the field taking what Cancel leaves.
    static let cancelWidth: CGFloat = 72
    /// The space above the top row.
    static let topPadding: CGFloat = unit
    /// From the bottom row's lower edge to the screen's bottom edge: Safari's (measured on
    /// an iPhone 17 Pro, iOS 26), so the rows sit on the home indicator's strip, not in it. Not a multiple of the unit.
    static let edgeClearance: CGFloat = 34
    /// The home indicator's strip on a phone that has one; what `ChromeState.homeInset` assumes until
    /// the host has measured it.
    static let homeIndicatorStrip: CGFloat = 34

    /// The one height of every piece, in every row and state: Safari's address bar and buttons (measured on
    /// an iPhone 17 Pro, iOS 26).
    static let barHeight: CGFloat = 12 * unit
    /// Hit areas never go below this, whatever they look like.
    static let minTapTarget: CGFloat = 44
    /// How far a piece's hit area reaches past its glass: none while the glass is itself at least
    /// `minTapTarget` tall, so neighbouring hit areas never overlap.
    static let hitOutset: CGFloat = max(0, (minTapTarget - barHeight) / 2)
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
    /// The playing bars in Listen's circle: smaller than a glyph, so four bars read as a level meter.
    static let playingBarsHeight: CGFloat = 4 * unit

    // MARK: - The bubble (the folded chrome)

    /// What both rows fold into once a scroll down has taken them, as Safari's address bar does: a small
    /// glass capsule centred at the foot naming the page (a domain, a title), the field shrunk. A tap on it
    /// brings the rows back. It is `bubbleHeight` tall, its lower edge `bubbleClearance` above the screen's
    /// edge (just over the home indicator), as wide as its text and `bubbleSidePadding` each side, at most
    /// margin to margin.
    static let bubbleHeight: CGFloat = 9 * unit
    /// From the bubble's lower edge to the screen's edge: lower than the rows' `edgeClearance`, so the
    /// folded chrome keeps a 58 pt footprint.
    static let bubbleClearance: CGFloat = 18
    /// Fixed like every glyph and label here: it never grows with text size (a long press shows it large).
    static let bubbleFontSize: CGFloat = 13
    /// Between the bubble's text and its ends.
    static let bubbleSidePadding: CGFloat = 4 * unit
    /// How far the hit area reaches past the bubble above and below: `minTapTarget` tall.
    static let bubbleHitOutset: CGFloat = max(0, (minTapTarget - bubbleHeight) / 2)

    /// Where a chrome field's text starts, from the capsule's leading end (its glyph slot, then `Spacing.xs`),
    /// and its size at the default text size (`TypeStyle.row`): the bubble's name starts there, at that size,
    /// so the field's text reads as becoming it.
    static let fieldTextInset: CGFloat = endInset + endGlyphSlot + 2 * unit
    static let fieldTextSize: CGFloat = 16

    /// The bubble's width for text `textWidth` wide: the text and its side padding, never narrower than a
    /// circle. `ChromeLayout` caps it to the margins.
    static func bubbleWidth(forTextWidth textWidth: CGFloat) -> CGFloat {
        max(bubbleHeight, textWidth + 2 * bubbleSidePadding)
    }

    /// How far above the top piece the fade behind the chrome starts.
    static let fadeRise: CGFloat = 50

    /// Listen's player card, at the foot of Listen: its corner radius (not a bar's). It sizes to its rows.
    static let cardRadius: CGFloat = 6 * unit

    /// What the chrome covers at the bottom of a scrolling screen, from the screen's edge: two rows,
    /// the same on every destination, so a screen never resizes when the chrome folds (142 pt).
    static let footprint: CGFloat = topPadding + barHeight + gap + barHeight + edgeClearance
    /// One row: the keyboard's form, and the fold's first step (86 pt).
    static let collapsedFootprint: CGFloat = topPadding + barHeight + edgeClearance
    /// The fold's end: the bubble (58 pt).
    static let bubbleFootprint: CGFloat = topPadding + bubbleHeight + bubbleClearance
    /// What the chrome covers at a fold step (`ChromeScroll.drawnStep`): 0 two rows, 1 one row, 2 the bubble.
    static func footprint(step: Int) -> CGFloat {
        step <= 0 ? footprint : step == 1 ? collapsedFootprint : bubbleFootprint
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
