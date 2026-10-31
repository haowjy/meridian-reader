import CoreGraphics

/// One piece of the chrome: where it is and whether it is in the tree (`ChromePieces` draws only
/// a piece that is shown, and glass fades in and out with it).
struct ChromePiece: Equatable {
    var rect: CGRect
    var isShown: Bool
    /// How much of its content (labels, glyphs) is drawn. Inside the glass container an opacity never
    /// fades glass, so a piece at 0 is bare glass.
    var opacity: CGFloat = 1

    /// Capsules and circles: half the height.
    var radius: CGFloat { rect.height / 2 }
}

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.rowsHeight`
/// high whose bottom edge is the safe area's: the bottom row ends on it, the top of the home
/// indicator's strip (`ChromeMetrics.rowLift` above it on a phone without one). Only the bubble
/// reaches into the strip, `bubbleClearance` above the screen's edge (`state.homeInset` below the box). Pure: the same state always gives the same frames, so the widths are checkable
/// without a screen. A scroll down (`state.fold`) folds in two steps, every piece going straight down,
/// never sideways: row 2 slides off the bottom while row 1 drops into its place (0 to 0.5), then ‹ › and
/// Listen slide off the bottom while the field's capsule shrinks into the bubble and its text turns into
/// the bubble's name (0.5 to 1). The keyboard's form (`state.keyboard`) is its own one row.
///
/// ```
/// expanded    [‹][›][ address / search             ][🎧]     row 1: Listen ends it on every destination
///             [ Library  |  Browser  |  Settings      ]     row 2: the pill alone, margin to margin
/// one row     [‹][›][ address / search             ][🎧]     the fold's first step: row 1 in row 2's place
/// folded                     ( example.com )                 the bubble: the field shrunk, over the home indicator
/// reader mode [‹][›][ address                      ][🎧]     the Browser's page as the Reader draws it
///             [‹][ Aa  site                         ][🎧]     the Library's Read
/// editing     [‹][ search                                ]   no Listen
///             [ the selection's actions                 ]   row 2 whole: no pill
/// keyboard    [ 🔍 field                      ⊗ 🎤 ][Cancel]    margin to margin on every phone: the field, one gap, Cancel
/// full screen (nothing)
/// ```
///
/// The pill keeps one place, row 2 whole, in every expanded form. There is no ⋯: each screen's menu is
/// on its title line, the Browser's on the field's leading glyph (a press and hold).
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
    /// Cancel (a word, `ChromeMetrics.cancelWidth` wide), ending the keyboard's row.
    var cancel: ChromePiece
    /// A Library selection's actions: row 2 whole, in place of the pill.
    var editBar: ChromePiece
    /// Listen, the round button at the end of row 1: opens Listen over everything.
    var listen: ChromePiece
    /// What a scroll down folds the rows into: a small glass capsule naming the page, centred at the foot.
    /// It takes over from the field's glass at the field's rect and shrinks to its own; its hit area is
    /// `ChromeMetrics.bubbleHitOutset` more above and below. Its `opacity` is its name's.
    var bubble: ChromePiece
    /// The bubble's name: its leading edge from the bubble's, and its scale (anchored there) on
    /// `TypeStyle.caption.size`. It starts where the field's text is, at its size, and ends centred.
    var bubbleTextX: CGFloat = 0
    var bubbleTextScale: CGFloat = 1

    /// The top edge of the highest piece, nil when nothing shows (full screen).
    var top: CGFloat? {
        [pill, field, nav, cancel, editBar, listen, bubble].filter(\.isShown).map(\.rect.minY).min()
    }

    init(width w: CGFloat, state s: ChromeState) {
        typealias K = ChromeMetrics
        let bar = Control.bar, gap = Spacing.xs, rowGap = Spacing.xs, margin = Spacing.bandMargin
        // The box's foot is the safe area's bottom: the rows end on the home indicator's strip (`rowLift`
        // above it where it is shallow); the keyboard's form sits on the keyboard.
        let bottom = K.rowsHeight - (s.keyboard ? 0 : K.rowLift(home: s.homeInset))
        let rowY = bottom - bar
        // Both rows share one pair of edges, the margins, on every width.
        let row1Y = rowY - gap - bar
        let isBrowse = s.destination == .browse
        let hold = !s.fullScreen
        /// ‹ ›'s capsule for this many arrows (0, 1 or 2).
        func navWidth(_ arrows: CGFloat) -> CGFloat { arrows >= 2 ? K.navPairWidth : arrows * K.navSingleWidth }
        let row2 = !s.editing && hold

        // Typing: only the field and Cancel (no pill), so the field runs from the left margin to Cancel,
        // which ends at the right margin, on every phone.
        let typing = s.keyboard && !s.editing && hold
        let cancelRect = CGRect(x: w - margin - K.cancelWidth, y: rowY, width: K.cancelWidth, height: bar)
        // The field's right end while typing: Cancel's left, or the right margin during Edit (no Cancel then).
        let rightEdge = typing ? cancelRect.minX - rowGap : w - margin

        cancel = ChromePiece(rect: cancelRect, isShown: typing)
        editBar = ChromePiece(rect: CGRect(x: margin, y: rowY, width: w - 2 * margin, height: bar),
                              isShown: s.editing && hold)
        pill = ChromePiece(rect: CGRect(x: margin, y: rowY, width: w - 2 * margin, height: bar), isShown: row2 && !typing)

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

        // The fold, in two steps, everything going down. First (0 to 0.5) row 2 slides off the bottom while
        // row 1 drops into its place. Then (0.5 to 1) ‹ › and Listen slide off the bottom, and the field's
        // text fades as the bubble's name fades in where it was, at its size; the field's glass hands over to
        // the bubble's (one shape all the way), which shrinks from the field's rect to its own while the
        // name glides to its centre and shrinks to the bubble's size. Labels and glyphs fade before their
        // glass goes; a piece leaves the tree once it is below the screen's edge.
        let f = s.fold
        let first = K.ramp(f, 0...0.5)
        let bubbleWidth = min(w - 2 * margin, s.bubbleWidth)
        // The bubble alone is placed from the screen's edge, inside the strip.
        let bubbleBottom = K.rowsHeight + s.homeInset - K.bubbleClearance
        let bubbleRect = CGRect(x: (w - bubbleWidth) / 2, y: bubbleBottom - Control.small, width: bubbleWidth, height: Control.small)
        // From a row's place in the bottom row to below the screen's edge.
        let offScreen = bar + K.rowsHeight + s.homeInset - bottom
        let row2Gone = K.ramp(f, 0...0.5), row1Gone = K.ramp(f, 0.5...0.85)
        // The field hands its glass to the bubble at `handOver`; the bubble shrinks after it.
        let handOver: CGFloat = 0.6
        let shrink = K.ramp(f, handOver...1)
        let drop = first * (bar + gap)
        func down(_ p: ChromePiece, by gone: CGFloat, from y: CGFloat = 0) -> ChromePiece {
            guard f > 0 else { return p }
            return ChromePiece(rect: p.rect.offsetBy(dx: 0, dy: y + gone * offScreen), isShown: p.isShown && gone < 1,
                               opacity: 1 - K.ramp(gone, 0...0.6))
        }
        pill = down(pill, by: row2Gone)
        nav = down(navForm, by: row1Gone, from: drop)
        listen = down(listenForm, by: row1Gone, from: drop)

        let fieldDropped = fieldForm.rect.offsetBy(dx: 0, dy: drop)
        field = ChromePiece(rect: fieldDropped, isShown: fieldForm.isShown && f < handOver,
                            opacity: 1 - K.ramp(f, 0.5...handOver))
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * shrink }
        let shrinking = CGRect(x: lerp(fieldDropped.minX, bubbleRect.minX), y: lerp(fieldDropped.minY, bubbleRect.minY),
                               width: lerp(fieldDropped.width, bubbleRect.width), height: lerp(fieldDropped.height, bubbleRect.height))
        bubble = ChromePiece(rect: shrinking, isShown: hold && f > 0.5, opacity: K.ramp(f, 0.5...handOver))
        // The name: from the field's text (its inset, its size) to centred at the bubble's own size.
        let nameWidth = max(0, bubbleWidth - 2 * Spacing.m)
        bubbleTextX = lerp(K.fieldTextInset, (shrinking.width - nameWidth) / 2)
        bubbleTextScale = lerp(TypeStyle.row.size / TypeStyle.caption.size, 1)
    }
}
