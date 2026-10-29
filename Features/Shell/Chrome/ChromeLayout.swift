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

    /// Capsules and circles: half the bar's height, so the Reader's card (taller than a bar) keeps a
    /// bar's corners.
    var radius: CGFloat { min(fullHeight, ChromeMetrics.barHeight) / 2 }
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
/// is the mockups' `rectsFor`. A scroll down (`state.capsule`) shrinks every piece toward the
/// capsule, which grows where they were going; the keyboard's form (`state.keyboard`) is its own one row.
///
/// ```
/// expanded    [‹][›][ address / search                  ]        row 1; the Reader's is its card
///             [ Listen | Library | Browser ][▶][⋯]               row 2 (Listen: no ▶, the card has one)
/// folded                     [ example.com ]                     the capsule: both rows gone; never on Listen, whose card stays
/// reader mode [‹][›][ address                       ][🎧]     the Browser's page as the Reader draws it: Listen ends row 1
///             [‹][ Aa | ▶ Listen · 9 min               ]         the Library's Read: the Listen field is the field
/// editing     [ the selection's actions                 ]       row 2 whole: no pill, ▶ or ⋯
/// keyboard    [ 🔍 field                      ⊗ 🎤 ][Cancel]    margin to margin on every phone: the field, one gap, Cancel (no icon, ▶ or ⋯)
/// full screen (nothing)
/// ```
///
/// ▶ and ⋯ keep one place in every expanded form.
struct ChromeLayout: Equatable {
    /// The pill: the keyboard's form hides it (the field and Cancel take its row).
    var pill: ChromePiece
    /// The address, search or title field; the Reader's card while expanded.
    var field: ChromePiece
    /// ‹ and ›, one capsule two circles wide (one circle with ‹ alone).
    var nav: ChromePiece
    var play: ChromePiece
    /// Which of ‹ and › the capsule draws (the other's circle isn't there).
    var navShowsBack = false
    var navShowsForward = false
    /// ⋯, or Cancel (a word, `ChromeMetrics.cancelWidth` wide) while the keyboard is up.
    var more: ChromePiece
    /// A Library selection's actions: row 2 whole, in place of the pill, ▶ and ⋯.
    var editBar: ChromePiece
    /// The Browser's reader mode: the round control that listens to the page, at the end of row 1.
    var listen: ChromePiece
    /// What a scroll down folds the rows into: a name for the page, bottom-aligned with row 2. The
    /// rect is the capsule itself (28 pt tall); its hit area is `ChromeMetrics.capsuleHitOutset` more each side.
    var capsule: ChromePiece
    /// The pill's width while expanded: its segments are laid out in it.
    var expandedPillWidth: CGFloat

    /// The top edge of the highest piece, nil when nothing shows (full screen).
    var top: CGFloat? {
        [pill, field, nav, play, more, editBar, listen, capsule].filter(\.isShown).map(\.rect.minY).min()
    }

    init(width w: CGFloat, state s: ChromeState) {
        typealias K = ChromeMetrics
        let bar = K.barHeight, gap = K.gap, rowGap = K.rowGap, margin = K.margin
        let rowY = K.readerFootprint - K.bottomPadding - bar
        // The bottom row is one fixed-size block (`bottomRowWidth`, the SE's), centred on a wider phone: its left
        // and right edges are the margins on the SE and equal insets on anything wider. Never stretched.
        let rowX = max(margin, (w - K.bottomRowWidth) / 2)
        let rowRight = w - rowX
        let row1Y = rowY - gap - bar
        let isBrowse = s.destination == .browse, isReader = s.destination == .reader
        // Listen's card has the play button, so ▶ isn't drawn there: its slot stays empty (the pill never widens).
        let played: CGFloat = s.played && !isReader ? 1 : 0
        let hold = !s.fullScreen
        /// ‹ ›'s capsule for this many arrows (0, 1 or 2).
        func navWidth(_ arrows: CGFloat) -> CGFloat { arrows >= 2 ? K.navPairWidth : arrows * K.navSingleWidth }
        let row2 = !s.editing && hold

        // Typing: only the field and Cancel (no pill, ▶ or ⋯: nothing there needs to stay put), so the
        // row is not the fixed block: the field runs from the left margin to Cancel, which ends at the right
        // margin, on every phone.
        let typing = s.keyboard && !s.editing && hold
        // Row 2 keeps one slot for ▶ and ⋯ in every form.
        let moreRect = typing ? CGRect(x: w - margin - K.cancelWidth, y: rowY, width: K.cancelWidth, height: bar)
                              : CGRect(x: rowRight - bar, y: rowY, width: bar, height: bar)
        let playRect = CGRect(x: rowRight - bar - rowGap - bar, y: rowY, width: bar, height: bar)
        // The field's right end when the keyboard is up during Edit (no Cancel then): left of ▶'s slot.
        let rightEdge = typing ? moreRect.minX - rowGap : rowRight - bar - rowGap - bar - played * (bar + rowGap) - rowGap
        let leftEdge = typing ? margin : rowX

        more = ChromePiece(rect: moreRect, isShown: row2)
        play = ChromePiece(rect: playRect, isShown: played > 0 && row2 && !typing)
        editBar = ChromePiece(rect: CGRect(x: margin, y: rowY, width: w - 2 * margin, height: bar),
                              isShown: s.editing && hold)
        // Row 2 is [pill][▶ slot][⋯] on every destination and state: the pill is one fixed width (`K.pillWidth`), ▶'s slot is
        // reserved (empty before anything has played and on Listen), so tabs never move or resize it.
        expandedPillWidth = K.pillWidth

        pill = ChromePiece(rect: CGRect(x: rowX, y: rowY, width: expandedPillWidth, height: bar), isShown: row2 && !typing)

        // ‹ ›. In the Browser: the pair whenever either way is open, the one that isn't dimmed (so ›
        // never hides behind a lone ‹ after going back to the first page). Elsewhere (a Library page
        // read in place): ‹ alone. The keyboard's form has neither.
        let listens = isBrowse && s.readerMode
        let pair = isBrowse && (s.canGoBack || s.canGoForward)
        let back: CGFloat = pair || (s.readerMode && s.canGoBack) ? 1 : 0
        let forward: CGFloat = pair ? 1 : 0
        navShowsBack = !s.keyboard && back > 0
        navShowsForward = !s.keyboard && forward > 0
        let navExpanded = ChromePiece(rect: CGRect(x: margin, y: row1Y, width: navWidth(back + forward), height: bar),
                                      isShown: back + forward > 0 && hold)
        // The keyboard's form has no arrows.
        let navForm = ChromePiece(rect: navExpanded.rect, isShown: navExpanded.isShown && !s.keyboard)

        let fieldTyping = ChromePiece(rect: CGRect(x: leftEdge, y: rowY, width: max(0, rightEdge - leftEdge), height: bar),
                                      isShown: hold)
        let fieldExpanded: ChromePiece
        if isReader {
            fieldExpanded = ChromePiece(rect: CGRect(x: margin, y: rowY - gap - K.card, width: w - 2 * margin, height: K.card), isShown: hold)
        } else {
            let x = margin + navWidth(back + forward) + (back + forward > 0 ? rowGap : 0)
            let right = w - margin - (listens ? bar + rowGap : 0)
            fieldExpanded = ChromePiece(rect: CGRect(x: x, y: row1Y, width: right - x, height: bar), isShown: hold)
        }
        let fieldForm = s.keyboard ? fieldTyping : fieldExpanded
        // Where it ends row 1 it stays through the keyboard's move (its rect doesn't move; it only goes).
        let listenRect = CGRect(x: w - margin - bar, y: row1Y, width: bar, height: bar)
        let listenForm = ChromePiece(rect: listenRect, isShown: listens && hold && !s.keyboard)

        // The fold: every piece scales down about the capsule's centre over the first 60% of it while the
        // capsule grows from there over the last 60%, so the two overlap and the glass blends one into
        // the other. A piece or the capsule at zero size leaves the tree, which nobody sees.
        let c = s.capsule
        let centre = CGPoint(x: w / 2, y: K.readerFootprint - K.bottomPadding - K.capsuleHeight / 2)
        let away = 1 - K.ramp(c, 0...0.6), grown = K.ramp(c, 0.4...1)
        func scaled(_ p: ChromePiece, _ f: CGFloat) -> CGRect {
            CGRect(x: centre.x + (p.rect.minX - centre.x) * f, y: centre.y + (p.rect.minY - centre.y) * f,
                   width: p.rect.width * f, height: p.rect.height * f)
        }
        func receding(_ p: ChromePiece) -> ChromePiece {
            c > 0 ? ChromePiece(rect: scaled(p, away), isShown: p.isShown && away > 0, scale: away) : p
        }
        let capsuleFull = CGRect(x: centre.x - s.capsuleWidth / 2, y: centre.y - K.capsuleHeight / 2,
                                 width: s.capsuleWidth, height: K.capsuleHeight)
        capsule = ChromePiece(rect: scaled(ChromePiece(rect: capsuleFull, isShown: true), grown), isShown: hold && grown > 0)
        pill = receding(pill)
        play = receding(play)
        more = receding(more)
        nav = receding(navForm)
        field = receding(fieldForm)
        listen = receding(listenForm)
    }
}
