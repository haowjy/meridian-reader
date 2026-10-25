import CoreGraphics

/// One piece of the chrome: where it is and how much of it shows.
struct ChromePiece: Equatable {
    var rect: CGRect
    var opacity: CGFloat

    /// Capsules and circles: half the bar's height, so the Reader's card (taller than a bar) keeps a
    /// bar's corners.
    var radius: CGFloat { min(rect.height, ChromeMetrics.barHeight) / 2 }
    /// Pieces are always in the tree; one that has faded away takes no touches.
    var isInteractive: Bool { opacity > 0.2 }

    static func mix(_ a: ChromePiece, _ b: ChromePiece, _ t: CGFloat) -> ChromePiece {
        ChromePiece(rect: CGRect(x: lerp(a.rect.minX, b.rect.minX, t), y: lerp(a.rect.minY, b.rect.minY, t),
                                 width: lerp(a.rect.width, b.rect.width, t), height: lerp(a.rect.height, b.rect.height, t)),
                    opacity: lerp(a.opacity, b.opacity, t))
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
        [pill, field, nav, play, more, editBar].filter { $0.opacity > 0.3 }.map(\.rect.minY).min()
    }

    init(width w: CGFloat, state s: ChromeState) {
        typealias K = ChromeMetrics
        let bar = K.barHeight, gap = K.gap, margin = K.margin
        let rowY = K.readerFootprint - K.bottomPadding - bar
        let row1Y = rowY - gap - bar
        let isBrowse = s.destination == .browse, isReader = s.destination == .reader
        let played: CGFloat = s.played ? 1 : 0
        let hold: CGFloat = s.fullScreen ? 0 : 1
        let row2: CGFloat = s.editing ? 0 : hold

        // Row 2 keeps one slot for ▶ and ⋯ in every form.
        let moreRect = CGRect(x: w - margin - bar, y: rowY, width: bar, height: bar)
        let playRect = CGRect(x: moreRect.minX - gap - bar, y: rowY, width: bar, height: bar)
        let iconX = moreRect.minX - gap - bar - played * (bar + gap)
        let rightEdge = iconX - gap

        more = ChromePiece(rect: moreRect, opacity: row2)
        play = ChromePiece(rect: playRect, opacity: played * row2)
        editBar = ChromePiece(rect: CGRect(x: margin, y: rowY, width: w - 2 * margin, height: bar),
                              opacity: s.editing ? hold : 0)
        expandedPillWidth = w - 2 * margin - gap - bar - played * (bar + gap)
        fold = s.fold

        let pillExpanded = ChromePiece(rect: CGRect(x: margin, y: rowY, width: expandedPillWidth, height: bar), opacity: row2)
        let pillFolded = ChromePiece(rect: CGRect(x: iconX, y: rowY, width: bar, height: bar), opacity: row2)
        pill = .mix(pillExpanded, pillFolded, s.fold)

        // ‹ ›: both circles expanded. Folded, › gives way while ▶ shows, and the arrows give way to a
        // field that would be narrower than `minimumField` (never while the keyboard is up).
        let back: CGFloat = isBrowse && s.canGoBack ? 1 : 0
        let forward: CGFloat = isBrowse && s.canGoForward ? 1 : 0
        var foldedBack = s.keyboard ? 0 : back
        var foldedForward = s.keyboard ? 0 : forward * (1 - played)
        func foldedFieldX() -> CGFloat { margin + bar * (foldedBack + foldedForward) + (foldedBack + foldedForward > 0 ? gap : 0) }
        while rightEdge - foldedFieldX() < K.minimumField, foldedBack + foldedForward > 0 {
            if foldedForward > 0 { foldedForward = 0 } else { foldedBack = 0 }
        }
        let navExpanded = ChromePiece(rect: CGRect(x: margin, y: row1Y, width: bar * (back + forward), height: bar),
                                      opacity: back + forward > 0 ? hold : 0)
        let navFolded = ChromePiece(rect: CGRect(x: margin, y: rowY, width: bar * (foldedBack + foldedForward), height: bar),
                                    opacity: foldedBack + foldedForward > 0 ? hold : 0)
        nav = .mix(navExpanded, navFolded, s.fold)

        let fieldFolded = ChromePiece(rect: CGRect(x: foldedFieldX(), y: rowY, width: max(0, rightEdge - foldedFieldX()), height: bar),
                                      opacity: hold)
        let fieldExpanded: ChromePiece
        if isReader {
            fieldExpanded = ChromePiece(rect: CGRect(x: margin, y: rowY - gap - K.card, width: w - 2 * margin, height: K.card), opacity: hold)
        } else {
            let x = margin + bar * (back + forward) + (back + forward > 0 ? gap : 0)
            fieldExpanded = ChromePiece(rect: CGRect(x: x, y: row1Y, width: w - margin - x, height: bar), opacity: hold)
        }
        field = .mix(fieldExpanded, fieldFolded, s.fold)
    }
}
