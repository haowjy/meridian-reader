import CoreGraphics

/// One piece of the chrome: where it is and whether it is in the tree (`ChromePieces` draws only
/// a piece that is shown, and glass fades in and out with it).
struct ChromePiece: Equatable {
    var rect: CGRect
    var isShown: Bool

    /// Capsules and circles: half the bar's height, so the Reader's card (taller than a bar) keeps a
    /// bar's corners.
    var radius: CGFloat { min(rect.height, ChromeMetrics.barHeight) / 2 }
    /// A piece shown in only one of two forms stays through the move between them (its rect
    /// shrinks away where it should); the ends are the forms themselves.
    static func mix(_ a: ChromePiece, _ b: ChromePiece, _ t: CGFloat) -> ChromePiece {
        ChromePiece(rect: CGRect(x: lerp(a.rect.minX, b.rect.minX, t), y: lerp(a.rect.minY, b.rect.minY, t),
                                 width: lerp(a.rect.width, b.rect.width, t), height: lerp(a.rect.height, b.rect.height, t)),
                    isShown: t <= 0 ? a.isShown : t >= 1 ? b.isShown : a.isShown || b.isShown)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.readerFootprint`
/// high whose bottom edge is just above the home indicator. Pure: the same state always gives the
/// same frames, so the widths in the mockups' `width-table.md` are checkable without a screen. It
/// is the mockups' `rectsFor`: every piece is `mix(expanded, collapsed, progress)`, and the
/// keyboard's form is the collapsed one without arrows.
///
/// ```
/// expanded    [‹][›][ address / search                  ]        row 1; the Reader's is its card
///             [ Reader | Library | Browser ][▶][⋯]               row 2, every screen
/// collapsed   [‹][›][ address ][icon][▶][⋯]                      one row; the Reader's field is its title chip
/// editing     [ the selection's actions                 ]       row 2 whole: no pill, ▶ or ⋯
/// keyboard    [ field                    ][icon][▶][✕]
/// full screen (nothing)
/// ```
///
/// ▶ and ⋯ keep one place in every form; the pill's rect folds into the icon's.
struct ChromeLayout: Equatable {
    /// The pill, or the screen icon once folded: its rect mixes between the two, and
    /// `ChromePill` draws the lit segment into the icon.
    var pill: ChromePiece
    /// The address, search or title field; the Reader's card while expanded.
    var field: ChromePiece
    /// ‹ and ›, one capsule two circles wide (one circle with ‹ alone).
    var nav: ChromePiece
    var play: ChromePiece
    /// ⋯, or ✕ while the keyboard is up.
    var more: ChromePiece
    /// A Library selection's actions: row 2 whole, in place of the pill, ▶ and ⋯.
    var editBar: ChromePiece
    /// How far the pill has folded (`ChromeState.fold`).
    var fold: CGFloat
    /// The pill's width while expanded: its segments are laid out in it.
    var expandedPillWidth: CGFloat

    /// The top edge of the highest piece, nil when nothing shows (full screen).
    var top: CGFloat? {
        [pill, field, nav, play, more, editBar].filter(\.isShown).map(\.rect.minY).min()
    }

    init(width w: CGFloat, state s: ChromeState) {
        typealias K = ChromeMetrics
        let bar = K.barHeight, gap = K.gap, rowGap = K.rowGap, margin = K.margin
        let rowY = K.readerFootprint - K.bottomPadding - bar
        let row1Y = rowY - gap - bar
        let isBrowse = s.destination == .browse, isReader = s.destination == .reader
        let played: CGFloat = s.played ? 1 : 0
        let hold = !s.fullScreen
        /// ‹ ›'s capsule for this many arrows (0, 1 or 2).
        func navWidth(_ arrows: CGFloat) -> CGFloat { arrows >= 2 ? K.navPairWidth : arrows * K.navSingleWidth }
        let row2 = !s.editing && hold

        // Row 2 keeps one slot for ▶ and ⋯ in every form.
        let moreRect = CGRect(x: w - margin - bar, y: rowY, width: bar, height: bar)
        let playRect = CGRect(x: moreRect.minX - rowGap - bar, y: rowY, width: bar, height: bar)
        let iconX = moreRect.minX - rowGap - bar - played * (bar + rowGap)
        let rightEdge = iconX - rowGap

        more = ChromePiece(rect: moreRect, isShown: row2)
        play = ChromePiece(rect: playRect, isShown: s.played && row2)
        editBar = ChromePiece(rect: CGRect(x: margin, y: rowY, width: w - 2 * margin, height: bar),
                              isShown: s.editing && hold)
        expandedPillWidth = w - 2 * margin - rowGap - bar - played * (bar + rowGap)
        fold = s.fold

        let pillExpanded = ChromePiece(rect: CGRect(x: margin, y: rowY, width: expandedPillWidth, height: bar), isShown: row2)
        let pillFolded = ChromePiece(rect: CGRect(x: iconX, y: rowY, width: bar, height: bar), isShown: row2)
        pill = .mix(pillExpanded, pillFolded, s.fold)

        // ‹ ›: both circles expanded. Folded, › gives way while ▶ shows, and the arrows give way to a
        // field that would be narrower than `minimumField` (never while the keyboard is up).
        let back: CGFloat = (isBrowse || s.readerMode) && s.canGoBack ? 1 : 0
        let forward: CGFloat = isBrowse && s.canGoForward ? 1 : 0
        var foldedBack = s.keyboard ? 0 : back
        var foldedForward = s.keyboard ? 0 : forward * (1 - played)
        func foldedFieldX() -> CGFloat { margin + navWidth(foldedBack + foldedForward) + (foldedBack + foldedForward > 0 ? rowGap : 0) }
        while rightEdge - foldedFieldX() < K.minimumField, foldedBack + foldedForward > 0 {
            if foldedForward > 0 { foldedForward = 0 } else { foldedBack = 0 }
        }
        let navExpanded = ChromePiece(rect: CGRect(x: margin, y: row1Y, width: navWidth(back + forward), height: bar),
                                      isShown: back + forward > 0 && hold)
        let navFolded = ChromePiece(rect: CGRect(x: margin, y: rowY, width: navWidth(foldedBack + foldedForward), height: bar),
                                    isShown: foldedBack + foldedForward > 0 && hold)
        nav = .mix(navExpanded, navFolded, s.fold)

        let fieldFolded = ChromePiece(rect: CGRect(x: foldedFieldX(), y: rowY, width: max(0, rightEdge - foldedFieldX()), height: bar),
                                      isShown: hold)
        let fieldExpanded: ChromePiece
        if isReader {
            fieldExpanded = ChromePiece(rect: CGRect(x: margin, y: rowY - gap - K.card, width: w - 2 * margin, height: K.card), isShown: hold)
        } else {
            let x = margin + navWidth(back + forward) + (back + forward > 0 ? rowGap : 0)
            fieldExpanded = ChromePiece(rect: CGRect(x: x, y: row1Y, width: w - margin - x, height: bar), isShown: hold)
        }
        field = .mix(fieldExpanded, fieldFolded, s.fold)
    }
}
