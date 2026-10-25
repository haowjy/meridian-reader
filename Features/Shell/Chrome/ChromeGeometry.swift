import CoreGraphics

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.footprint` high
/// whose bottom edge is just above the home indicator. Pure: the same state always gives the same
/// frames, so the widths in `width-table.md` are checkable without a screen, and it mirrors
/// `MC.layout` in the mockups.
///
/// ```
/// expanded    [‹ ›][ address / search                  ]        row 1; the Reader has none
///             [ Reader | Library | Browser ][▶][⋯]              row 2, every screen
/// collapsed   [‹ ›][ address ][▶][icon][⋯]                      one row; the Reader's field is its title chip
/// editing     [ the selection's actions                 ]       row 2 whole: no pill, ▶ or ⋯
/// keyboard    [ field                    ][icon][✕]             one row, no ▶, no arrows
/// full screen (nothing)                                         no pieces, no fade
/// ```
struct ChromeGeometry: Equatable {
    /// The address, search or title field; nil on the expanded Reader, which has none.
    var field: CGRect?
    /// The ‹ and › buttons, nil when dropped.
    var back: CGRect?
    var forward: CGRect?
    /// The pill (expanded only).
    var pill: CGRect?
    var play: CGRect?
    /// A Library selection's actions: row 2 whole, in place of the pill, ▶ and ⋯.
    var editBar: CGRect?
    /// The current-screen icon (one row only).
    var icon: CGRect?
    /// ⋯, or ✕ while the keyboard is up.
    var more: CGRect?
    var rows: ChromeState.Rows
    /// The colour of what is under the pieces: opaque from `solidTop` down, fading in over
    /// `rise` above it. nil in full screen.
    var fade: Fade?

    struct Fade: Equatable {
        var solidTop: CGFloat
        var rise: CGFloat
        /// What the colour behind the pieces covers, down to the box's bottom.
        var height: CGFloat { ChromeMetrics.footprint - solidTop }
    }

    /// Where the prepare progress and the toast sit (the top edge of the highest piece), or nil
    /// when something else carries them: the expanded Reader and Now Playing float their own above
    /// their band, and full screen shows none.
    var overlayTop: CGFloat?

    var navigation: CGRect? { back.map { b in forward.map { b.union($0) } ?? b } }

    /// The top edge of the highest piece (the box's top when there is none).
    var top: CGFloat {
        [field?.minY, back?.minY, forward?.minY, pill?.minY, play?.minY, editBar?.minY, icon?.minY, more?.minY]
            .compactMap { $0 }.min() ?? ChromeMetrics.footprint
    }

    init(width w: CGFloat, state: ChromeState) {
        typealias M = ChromeMetrics
        rows = state.rows
        let bottom = M.footprint - M.bottomPadding
        let isBrowse = state.destination == .browse
        let isReader = state.destination == .reader

        switch rows {
        case .none:
            break
        case .one:
            // One row: every piece is `barHeight` high, circles that wide.
            let d = M.barHeight
            let rowTop = bottom - d
            let moreFrame = CGRect(x: w - M.margin - d, y: rowTop, width: d, height: d)
            more = moreFrame
            let iconFrame = CGRect(x: moreFrame.minX - M.gap - d, y: rowTop, width: d, height: d)
            icon = iconFrame
            var right = iconFrame.minX - M.gap
            if state.played, !state.keyboard {
                let p = CGRect(x: right - d, y: rowTop, width: d, height: d)
                play = p
                right = p.minX - M.gap
            }
            // The arrows: › goes first (always with a play button beside it), then ‹, as soon as the
            // address would fall under its minimum.
            var arrows = 0
            if isBrowse, !state.keyboard, state.canGoBack || state.canGoForward {
                arrows = state.canGoForward ? 2 : 1
                if state.played { arrows = min(arrows, 1) }
                while arrows > 0, right - (M.margin + CGFloat(arrows) * d + M.gap) < M.minimumField {
                    arrows -= 1
                }
            }
            (back, forward) = Self.arrows(count: arrows, left: M.margin, top: rowTop)
            let left = M.margin + (arrows > 0 ? CGFloat(arrows) * d + M.gap : 0)
            field = CGRect(x: left, y: rowTop, width: max(0, right - left), height: d)
        case .two:
            let h = M.barHeight
            let row2 = bottom - h
            if state.editing {
                editBar = CGRect(x: M.margin, y: row2, width: w - 2 * M.margin, height: h)
            } else {
                let moreFrame = CGRect(x: w - M.margin - h, y: row2, width: h, height: h)
                more = moreFrame
                var right = moreFrame.minX - M.gap
                if state.played {
                    let p = CGRect(x: right - h, y: row2, width: h, height: h)
                    play = p
                    right = p.minX - M.gap
                }
                pill = CGRect(x: M.margin, y: row2, width: max(0, right - M.margin), height: h)
            }

            if !isReader {
                let row1 = row2 - M.gap - h
                let arrows = isBrowse && (state.canGoBack || state.canGoForward) ? (state.canGoForward ? 2 : 1) : 0
                let navWidth = arrows == 2 ? M.navPairWidth : arrows == 1 ? M.navSingleWidth : 0
                (back, forward) = Self.arrows(count: arrows, left: M.margin, top: row1)
                let left = M.margin + (arrows > 0 ? navWidth + M.gap : 0)
                field = CGRect(x: left, y: row1, width: w - M.margin - left, height: h)
            }
        }

        if rows != .none {
            // The reading pages keep their own content clear of row 2 (their band stands above it):
            // no rise while it is expanded.
            let rise = isReader && rows == .two ? 0 : M.fadeHeight
            fade = Fade(solidTop: top - M.topPadding, rise: rise)
            if rows == .one || !isReader { overlayTop = top - M.topPadding }
        }
    }

    private static func arrows(count: Int, left: CGFloat, top: CGFloat) -> (CGRect?, CGRect?) {
        let d = ChromeMetrics.barHeight
        guard count > 0 else { return (nil, nil) }
        let back = CGRect(x: left, y: top, width: d, height: d)
        guard count > 1 else { return (back, nil) }
        return (back, CGRect(x: left + d, y: top, width: d, height: d))
    }
}
