import CoreGraphics

/// The compact bottom chrome's layout. Everything that places a piece reads from here and from the
/// shared scales (`Control`, `Spacing`, `Glyph`, `TypeStyle`): `ChromeLayout` places the pieces with
/// them, and no other file holds a bar measure. Every piece `Control.chrome` (44) but the pill, `Control.tabBar` (48), `Spacing.xs` 8 between
/// the rows and between two pieces on a row, `Spacing.bandMargin` 12 at the sides, `Spacing.xxs` 4 above
/// the top row, the bubble `Control.small` 36 with `Spacing.m` 16 each side of its name.
///
/// One shape language and two heights: every floating piece is a Capsule or a Circle `Control.chrome`
/// high (the search and address fields, ‹ ›, Listen, Cancel, the keyboard's row, and the reading pages' top
/// group) but the pill, `Control.tabBar` high, so its corner radius is half its height, and every one is at
/// least `Control.tap` to tap (`hitOutset` / `pillHitOutset` past its glass, none at or above the tap floor).
/// The bottom row ends on the home indicator's strip (the safe area's bottom, as measured), as Safari's
/// does; the keyboard's row ends on the keyboard. Scrolling down folds in steps: row 2 goes (the field drops to its place), then
/// the field shrinks into the bubble (`Control.small` tall), a small glass capsule naming the page just
/// above the home indicator; a tap on it, or a scroll up, brings both rows back. Changing `Control.chrome`
/// or `Control.tabBar` changes every piece and every footprint; nothing else needs editing.
///
/// The chrome's box is `rowsHeight` tall, its foot on the safe area's bottom. What it covers is measured
/// from there (`clearance(step:home:)`, what a view laid out above the safe area keeps clear); a view laid
/// out to the screen's edge adds the strip itself. The bubble is the one piece placed from the screen's
/// edge (`bubbleClearance`), below the strip's top.
///
/// The pill's lit segment is a capsule inset by `Spacing.xxs` on all four sides, so it is
/// `pillLitHeight` tall and its radius is the pill's minus the inset (concentric).
enum ChromeMetrics {
    /// Cancel's width while a search is editing: a word, not a circle. The keyboard's row is
    /// [field][Cancel] from margin to margin on every phone, the field taking what Cancel leaves.
    static let cancelWidth: CGFloat = 72
    /// The home indicator's strip on a phone that has one; what `ChromeState.homeInset` assumes until
    /// the host has measured it.
    static let homeIndicatorStrip: CGFloat = 34
    /// The chrome's box: the room above row 1, row 1, the gap and row 2 (104 pt), its foot on the safe area's
    /// bottom.
    static let rowsHeight: CGFloat = Spacing.xxs + Control.chrome + Spacing.xs + Control.tabBar
    /// How far above the safe area's bottom the rows end: on it, except where the strip is shallower than
    /// `bubbleClearance` (a phone with a Home button has none), where they end that far above the screen's
    /// edge, as the bubble does, so a row never sits on the edge. Not the keyboard's row: it sits on the keyboard.
    static func rowLift(home: CGFloat) -> CGFloat { max(0, bubbleClearance - home) }

    /// How far a piece's hit area reaches past its glass so it is `Control.tap` to tap: 0 while the chrome
    /// is at least the tap floor; with the `Spacing.xs` gaps neighbouring hit areas never overlap.
    static let hitOutset: CGFloat = max(0, (Control.tap - Control.chrome) / 2)
    /// The same for the pill's segments, above and below its glass.
    static let pillHitOutset: CGFloat = max(0, (Control.tap - Control.tabBar) / 2)
    /// A circle inset `Spacing.xxs` inside a piece (36 pt), concentric with it: the address field's lit
    /// reader icon.
    static let innerCircle: CGFloat = Control.chrome - 2 * Spacing.xxs
    /// The pill's lit segment, a capsule inset `Spacing.xxs` inside it (40 pt), concentric with it; a
    /// segment's glyph and name fit inside it or the name goes.
    static let pillLitHeight: CGFloat = Control.tabBar - 2 * Spacing.xxs
    /// The glyph slot at each end of a capsule, and its inset from the capsule's end, top and bottom
    /// (concentric: the slot's corners follow the end cap's, `Control.chrome / 2 - endInset`). Also a band
    /// field's leading slot (🔍, or on a loaded page its 📄 / spinner), so the text starts at one place.
    static let endGlyphSlot: CGFloat = Glyph.slot
    static let endInset: CGFloat = (Control.chrome - endGlyphSlot) / 2
    /// ‹ alone is a circle; with › it is a capsule of two circles' width, with ⌂ too three.
    static let navSingleWidth: CGFloat = Control.chrome
    static let navPairWidth: CGFloat = 2 * Control.chrome
    /// How far a circle's hit area in the ‹ › ⌂ capsule reaches past it at its leading and trailing sides,
    /// for circle `index` of `count`. Alone, `hitOutset` each side. Side by side neighbours meet at their shared
    /// edge (neither reaches into the other) and the two ends make up `Control.tap` outward instead: the first
    /// into the margin, the last into the gap before the field. A middle circle (› between ‹ and ⌂) has only its
    /// own 44 pt, enough while the chrome is at least the tap floor. All 0 while it is.
    static func navHitSides(index: Int, of count: Int) -> (leading: CGFloat, trailing: CGFloat) {
        guard count > 1 else { return (hitOutset, hitOutset) }
        return (index == 0 ? 2 * hitOutset : 0, index == count - 1 ? 2 * hitOutset : 0)
    }

    // MARK: - The bubble (the folded chrome)

    /// What both rows fold into once a scroll down has taken them, as Safari's address bar does: a small
    /// glass capsule `Control.small` tall centred at the foot naming the page (a domain, a title, in
    /// `TypeStyle.caption`'s size, fixed: a long press shows it large), the field shrunk. A tap on it
    /// brings the rows back. Its lower edge is `bubbleClearance` above the screen's edge (just over the
    /// home indicator), below the strip's top where the rows end: the one piece placed from the screen's edge,
    /// so the folded chrome covers 58 pt from it on every phone.
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

    /// What the chrome covers above the safe area's bottom at a fold step (`ChromeScroll.drawnStep`), a strip
    /// `home` deep under it: 0 two rows (104 pt over a 34 pt strip), 1 one row (48), 2 the bubble (24). The
    /// same at step 0 on every destination, so a screen never resizes when the chrome folds; an in-place
    /// reader keeps step 0's (its chrome never folds). From the screen's edge, add `home` (138, 82, 58).
    static func clearance(step: Int, home: CGFloat) -> CGFloat {
        switch step {
        case ...0: rowsHeight + rowLift(home: home)
        case 1: Spacing.xxs + Control.chrome + rowLift(home: home)
        default: max(0, Spacing.xxs + Control.small + bubbleClearance - home)
        }
    }
    /// The keyboard's row and the room above it, over the keyboard (48 pt).
    static let keyboardClearance: CGFloat = Spacing.xxs + Control.chrome

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
