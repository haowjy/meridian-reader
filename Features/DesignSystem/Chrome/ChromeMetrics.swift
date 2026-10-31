import CoreGraphics

/// The compact bottom chrome's layout. Everything that places a piece reads from here and from the
/// shared scales (`Control`, `Spacing`, `Glyph`, `TypeStyle`): `ChromeLayout` places the pieces with
/// them, and no other file holds a bar measure. The sizes are Safari's (measured on an iPhone 17 Pro,
/// iOS 26) and the mockups' `SZ` (`chrome.js`): every piece `Control.bar` 48, `Spacing.xs` 8 between
/// the rows and between two pieces on a row, `Spacing.bandMargin` 12 at the sides, `Spacing.xxs` 4 above
/// the top row, the bubble `Control.small` 36 with `Spacing.m` 16 each side of its name.
///
/// One shape language and one height: every floating piece is a Capsule or a Circle `Control.bar`
/// high (the pill, the search and address fields, ‹ ›, Listen, ⋯, ✕, the keyboard's row), so its
/// corner radius is half that, and every one is at least `Control.tap` to tap.
/// The bottom row ends `edgeClearance` above the screen's edge, on the home indicator's strip as
/// Safari's does. Scrolling down folds in steps: row 2 goes (the field drops to its place), then
/// the field shrinks into the bubble (`Control.small` tall), a small glass capsule naming the page just
/// above the home indicator; a tap on it, or a scroll up, brings both rows back. Changing `Control.bar`
/// changes every piece and every footprint.
///
/// Footprints are measured from the screen's bottom edge (the home indicator's strip included);
/// `aboveSafeArea` turns one into what a view laid out above the safe area keeps clear.
///
/// The pill's lit segment is a capsule inset by `Spacing.xxs` on all four sides, so it is
/// `Control.bar - 2 * Spacing.xxs` tall and its radius is the pill's minus the inset (concentric).
enum ChromeMetrics {
    /// Cancel's width while a search is editing: a word, not a circle. The keyboard's row is
    /// [field][Cancel] from margin to margin on every phone, the field taking what Cancel leaves.
    static let cancelWidth: CGFloat = 72
    /// From the bottom row's lower edge to the screen's bottom edge: Safari's, so the rows sit on
    /// the home indicator's strip, not in it.
    static let edgeClearance: CGFloat = 34
    /// The home indicator's strip on a phone that has one; what `ChromeState.homeInset` assumes until
    /// the host has measured it.
    static let homeIndicatorStrip: CGFloat = 34

    /// How far a piece's hit area reaches past its glass: none while the glass is itself at least
    /// `Control.tap` tall, so neighbouring hit areas never overlap.
    static let hitOutset: CGFloat = max(0, (Control.tap - Control.bar) / 2)
    /// The glyph slot at each end of a capsule, and its inset from the capsule's end, top and bottom
    /// (concentric: the slot's corners follow the end cap's, `Control.bar / 2 - endInset`). Also a band
    /// field's leading slot (🔍, or on a loaded page its 📄 / spinner), so the text starts at one place.
    static let endGlyphSlot: CGFloat = 24
    static let endInset: CGFloat = (Control.bar - endGlyphSlot) / 2
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = Control.bar
    static let navPairWidth: CGFloat = 2 * Control.bar

    // MARK: - The bubble (the folded chrome)

    /// What both rows fold into once a scroll down has taken them, as Safari's address bar does: a small
    /// glass capsule `Control.small` tall centred at the foot naming the page (a domain, a title, in
    /// `TypeStyle.caption`'s size, fixed: a long press shows it large), the field shrunk. A tap on it
    /// brings the rows back. Its lower edge is `bubbleClearance` above the screen's edge (just over the
    /// home indicator), lower than the rows' `edgeClearance`, so the folded chrome keeps a 58 pt footprint.
    static let bubbleClearance: CGFloat = 18
    /// How far the hit area reaches past the bubble above and below: `Control.tap` tall.
    static let bubbleHitOutset: CGFloat = max(0, (Control.tap - Control.small) / 2)

    /// Where a chrome field's text starts, from the capsule's leading end (its glyph slot, then `Spacing.xs`).
    /// Its size at the default text size is `TypeStyle.row`'s: the bubble's name starts there, at that size,
    /// so the field's text reads as becoming it.
    static let fieldTextInset: CGFloat = endInset + endGlyphSlot + Spacing.xs

    /// The bubble's width for text `textWidth` wide: the text and its side padding, never narrower than a
    /// circle. `ChromeLayout` caps it to the margins.
    static func bubbleWidth(forTextWidth textWidth: CGFloat) -> CGFloat {
        max(Control.small, textWidth + 2 * Spacing.m)
    }

    /// How far above the top piece the fade behind the chrome starts.
    static let fadeRise: CGFloat = 50

    /// What the chrome covers at the bottom of a scrolling screen, from the screen's edge: two rows,
    /// the same on every destination, so a screen never resizes when the chrome folds (142 pt).
    static let footprint: CGFloat = Spacing.xxs + Control.bar + Spacing.xs + Control.bar + edgeClearance
    /// One row: the keyboard's form, and the fold's first step (86 pt).
    static let collapsedFootprint: CGFloat = Spacing.xxs + Control.bar + edgeClearance
    /// The fold's end: the bubble (58 pt).
    static let bubbleFootprint: CGFloat = Spacing.xxs + Control.small + bubbleClearance
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
