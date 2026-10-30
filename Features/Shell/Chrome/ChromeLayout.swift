import CoreGraphics

/// One piece of the chrome: where it is and whether it is in the tree (`ChromePieces` draws only
/// a piece that is shown, and glass fades in and out with it).
struct ChromePiece: Equatable {
    var rect: CGRect
    var isShown: Bool
    /// How far the fold has shrunk it: its content is laid out at `fullWidth` by `fullHeight` and scaled by
    /// this, so a label is drawn smaller as the piece shrinks and never reflowed (clipped, truncated) into it.
    var scale: CGFloat = 1

    var fullWidth: CGFloat { scale > 0 ? rect.width / scale : rect.width }
    var fullHeight: CGFloat { scale > 0 ? rect.height / scale : rect.height }

    /// Capsules and circles: half the bar's height.
    var radius: CGFloat { fullHeight / 2 }
    /// A piece shown in only one of two forms stays through the move between them (its rect
    /// shrinks away where it should); the ends are the forms themselves.
    static func mix(_ a: ChromePiece, _ b: ChromePiece, _ t: CGFloat) -> ChromePiece {
        ChromePiece(rect: CGRect(x: lerp(a.rect.minX, b.rect.minX, t), y: lerp(a.rect.minY, b.rect.minY, t),
                                 width: lerp(a.rect.width, b.rect.width, t), height: lerp(a.rect.height, b.rect.height, t)),
                    isShown: t <= 0 ? a.isShown : t >= 1 ? b.isShown : a.isShown || b.isShown)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.footprint`
/// high whose bottom edge is the safe area's. The rows reach below the box, into the home
/// indicator's strip: the bottom row ends `edgeClearance` above the screen's edge (`state.homeInset`
/// below the box). Pure: the same state always gives the same frames, so the widths are checkable
/// without a screen. A scroll down (`state.fold`) folds in two steps: row 2 shrinks away while row 1
/// drops into its place (0 to 0.5), then row 1 shrinks toward the strip, whose text comes up where it
/// went (0.5 to 1). The keyboard's form (`state.keyboard`) is its own one row.
///
/// ```
/// expanded    [‹][›][ address / search             ][🎧]     row 1: Listen ends it on every destination
///             [ Library | Browser ]               [⋯]       row 2
/// one row     [‹][›][ address / search             ][🎧]     the fold's first step: row 1 in row 2's place
/// folded                       example.com                   the strip: text over the home indicator
/// reader mode [‹][›][ address                      ][🎧]     the Browser's page as the Reader draws it
///             [‹][ Aa  site                         ][🎧]     the Library's Read
/// editing     [‹][ search                                ]   no Listen
///             [ the selection's actions                 ]   row 2 whole: no pill or ⋯
/// keyboard    [ 🔍 field                      ⊗ 🎤 ][Cancel]    margin to margin on every phone: the field, one gap, Cancel
/// full screen (nothing)
/// ```
///
/// The pill keeps one place at the left of row 2 and ⋯ one at its right, in every expanded form.
struct ChromeLayout: Equatable {
    /// The pill: the keyboard's form hides it (the field and Cancel take its row).
    var pill: ChromePiece
    /// The address, search or title field.
    var field: ChromePiece
    /// ‹ and ›, one capsule two circles wide (one circle with ‹ alone).
    var nav: ChromePiece
    /// Which of ‹ and › the capsule draws (the other's circle isn't there).
    var navShowsBack = false
    var navShowsForward = false
    /// ⋯, or Cancel (a word, `ChromeMetrics.cancelWidth` wide) while the keyboard is up.
    var more: ChromePiece
    /// A Library selection's actions: row 2 whole, in place of the pill and ⋯.
    var editBar: ChromePiece
    /// Listen, the round button at the end of row 1: opens Listen over everything.
    var listen: ChromePiece
    /// What a scroll down folds the rows into: a name for the page, its lower edge where row 2's is.
    /// The rect is the strip's text box (20 pt tall); its hit area is `ChromeMetrics.stripHitOutset` more each side.
    var strip: ChromePiece
    /// How far the strip's text has come up (0 to 1): it fades and rises in, it does not grow.
    var stripOpacity: CGFloat = 0

    /// The top edge of the highest piece, nil when nothing shows (full screen).
    var top: CGFloat? {
        [pill, field, nav, more, editBar, listen, strip].filter(\.isShown).map(\.rect.minY).min()
    }

    init(width w: CGFloat, state s: ChromeState) {
        typealias K = ChromeMetrics
        let bar = K.barHeight, gap = K.gap, rowGap = K.rowGap, margin = K.margin
        // The rows dip into the home indicator's strip; the keyboard's form sits on the keyboard instead.
        let bottom = K.footprint + (s.keyboard ? 0 : s.homeInset - K.edgeClearance)
        let rowY = bottom - bar
        // Both rows share one pair of edges, the margins, on every width. The pill keeps its fixed width
        // at the left and ⋯ ends the row at the right; a wider screen only widens the gap between them.
        let row1Y = rowY - gap - bar
        let isBrowse = s.destination == .browse
        let hold = !s.fullScreen
        /// ‹ ›'s capsule for this many arrows (0, 1 or 2).
        func navWidth(_ arrows: CGFloat) -> CGFloat { arrows >= 2 ? K.navPairWidth : arrows * K.navSingleWidth }
        let row2 = !s.editing && hold

        // Typing: only the field and Cancel (no pill or ⋯: nothing there needs to stay put), so the
        // field runs from the left margin to Cancel, which ends at the right margin, on every phone.
        let typing = s.keyboard && !s.editing && hold
        let moreRect = typing ? CGRect(x: w - margin - K.cancelWidth, y: rowY, width: K.cancelWidth, height: bar)
                              : CGRect(x: w - margin - bar, y: rowY, width: bar, height: bar)
        // The field's right end while typing: Cancel's left, or the right margin during Edit (no Cancel then).
        let rightEdge = typing ? moreRect.minX - rowGap : w - margin

        more = ChromePiece(rect: moreRect, isShown: row2)
        editBar = ChromePiece(rect: CGRect(x: margin, y: rowY, width: w - 2 * margin, height: bar),
                              isShown: s.editing && hold)
        pill = ChromePiece(rect: CGRect(x: margin, y: rowY, width: K.pillWidth, height: bar), isShown: row2 && !typing)

        // ‹ ›. In the Browser: the pair whenever either way is open, the one that isn't dimmed (so ›
        // never hides behind a lone ‹ after going back to the first page). Elsewhere (a Library page
        // read in place): ‹ alone. The keyboard's form has neither.
        let pair = isBrowse && (s.canGoBack || s.canGoForward)
        let back: CGFloat = pair || (s.readerMode && s.canGoBack) ? 1 : 0
        let forward: CGFloat = pair ? 1 : 0
        navShowsBack = !s.keyboard && back > 0
        navShowsForward = !s.keyboard && forward > 0
        let navExpanded = ChromePiece(rect: CGRect(x: margin, y: row1Y, width: navWidth(back + forward), height: bar),
                                      isShown: back + forward > 0 && hold)
        // The keyboard's form has no arrows.
        let navForm = ChromePiece(rect: navExpanded.rect, isShown: navExpanded.isShown && !s.keyboard)

        // Listen ends row 1, but for the keyboard's form and Edit (where row 1 is the search alone).
        let listens = !s.keyboard && !s.editing && hold
        let fieldTyping = ChromePiece(rect: CGRect(x: margin, y: rowY, width: max(0, rightEdge - margin), height: bar),
                                      isShown: hold)
        let x = margin + navWidth(back + forward) + (back + forward > 0 ? rowGap : 0)
        let right = w - margin - (listens ? bar + rowGap : 0)
        let fieldExpanded = ChromePiece(rect: CGRect(x: x, y: row1Y, width: right - x, height: bar), isShown: hold)
        let fieldForm = s.keyboard ? fieldTyping : fieldExpanded
        // Where it ends row 1 it stays through the keyboard's move (its rect doesn't move; it only goes).
        let listenForm = ChromePiece(rect: CGRect(x: w - margin - bar, y: row1Y, width: bar, height: bar), isShown: listens)

        // The fold, in two steps. First (0 to 0.5) row 2 shrinks about its own middle and goes, while
        // row 1 drops into its place. Then (0.5 to 1) row 1 shrinks toward the strip's middle and goes,
        // while the strip's text comes up. A piece at zero size leaves the tree, which nobody sees.
        let f = s.fold
        let first = K.ramp(f, 0...0.5), second = K.ramp(f, 0.5...1)
        let row2Centre = CGPoint(x: w / 2, y: rowY + bar / 2)
        let centre = CGPoint(x: w / 2, y: bottom - K.stripHeight / 2)
        let row2Away = 1 - K.ramp(f, 0...0.35), row1Away = 1 - K.ramp(f, 0.5...0.85), grown = K.ramp(f, 0.7...1)
        let drop = first * (bar + gap)
        func scaled(_ r: CGRect, about c: CGPoint, _ k: CGFloat) -> CGRect {
            CGRect(x: c.x + (r.minX - c.x) * k, y: c.y + (r.minY - c.y) * k, width: r.width * k, height: r.height * k)
        }
        func foldRow2(_ p: ChromePiece) -> ChromePiece {
            f > 0 ? ChromePiece(rect: scaled(p.rect, about: row2Centre, row2Away), isShown: p.isShown && row2Away > 0, scale: row2Away) : p
        }
        func foldRow1(_ p: ChromePiece) -> ChromePiece {
            guard f > 0 else { return p }
            let r = p.rect.offsetBy(dx: 0, dy: drop)
            return ChromePiece(rect: scaled(r, about: centre, row1Away), isShown: p.isShown && row1Away > 0 && second < 1, scale: row1Away)
        }
        let stripFull = CGRect(x: centre.x - s.stripWidth / 2, y: centre.y - K.stripHeight / 2,
                               width: s.stripWidth, height: K.stripHeight)
        strip = ChromePiece(rect: stripFull, isShown: hold && grown > 0)
        stripOpacity = grown
        pill = foldRow2(pill)
        more = foldRow2(more)
        nav = foldRow1(navForm)
        listen = foldRow1(listenForm)
        field = foldRow1(fieldForm)
    }
}
