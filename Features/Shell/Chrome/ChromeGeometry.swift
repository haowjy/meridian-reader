import CoreGraphics

/// The compact bottom chrome's sizes, from the approved mockups (`width-table.md`). Everything
/// that sets a size reads from here; `ChromeGeometry` places the pieces with them.
///
/// One shape language: every floating piece is a Capsule or a Circle, so its corner radius is
/// half its height, and a circle's diameter is its row's height. Three heights, no others:
///
/// ```
/// row 1   52   ‹ (circle) or ‹ › (capsule), the address field, the Library search
/// row 2   56   the pill, ▶ (circle), ⋯ (circle)
/// one row 48   every piece when collapsed or searching
/// ```
///
/// The pill's lit segment is a capsule inset by `litInset` on all four sides, so its radius is
/// the pill's radius minus the inset (concentric), as in Apple Music's and Reddit's tab capsules.
///
/// Every size is a multiple of `unit` except `bottomPadding` (6, today's). The smaller scale the
/// design recommends (D) is a one-edit switch: row1Height 11 * unit, row2Height 12 * unit,
/// collapsedHeight 11 * unit, bottomPadding 2 * unit, labelSize 10 (heights 44 / 48 / 44, footprint
/// 112, collapsed 56). `tools/check-tokens.js` in the design folder compares this file with the mockups.
enum ChromeMetrics {
    /// The base unit every other size is a multiple of.
    static let unit: CGFloat = 4

    /// Left and right margin; also the gap between a row's pieces and the screen edge.
    static let margin: CGFloat = 3 * unit
    /// Gap between two pieces on a row, and between the rows.
    static let gap: CGFloat = 2 * unit
    /// The space above the top row and below the bottom row.
    static let topPadding: CGFloat = unit
    static let bottomPadding: CGFloat = 6

    /// Row 1 (expanded): the arrows, the address field, the Library search.
    static let row1Height: CGFloat = 13 * unit
    /// Row 2 (expanded): the pill, ▶, ⋯ and the edit bar.
    static let row2Height: CGFloat = 14 * unit
    /// The one row (collapsed or searching): every piece.
    static let collapsedHeight: CGFloat = 12 * unit
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = row1Height
    static let navPairWidth: CGFloat = 2 * row1Height

    /// The narrowest address field before the arrows give way to it.
    static let minimumField: CGFloat = 120
    /// The pill's lit segment is inset from the pill's edge and from its neighbours by this much,
    /// on all four sides.
    static let litInset = BottomChrome.litInset

    // Inside the pieces. Every glyph is `BottomChrome.iconSize`, medium weight.
    /// A pill segment's label, and the gap between it and its glyph.
    static let labelSize: CGFloat = 11
    static let segmentGap: CGFloat = 2
    /// The glyph's cell in a pill segment: the spinner takes the same room as the symbols.
    static let segmentGlyphHeight: CGFloat = 22
    /// The Reader segment while there is nothing to open.
    static let segmentDimmedOpacity = 0.55
    /// ▶'s progress ring: its line width and its inset from the circle.
    static let ringWidth: CGFloat = 2.5
    static let ringInset: CGFloat = 4
    /// The fade behind the chrome: page text dissolves over this height above the top piece and is
    /// fully covered from there down.
    static let fadeHeight: CGFloat = 28

    /// What the chrome reserves at the bottom of a scrolling screen (expanded), above the safe
    /// area: the same on every destination, so a screen never resizes when the chrome collapses.
    static let footprint: CGFloat = topPadding + row1Height + gap + row2Height + bottomPadding
    /// One row high: what a screen keeps clear while the chrome is collapsed or searching.
    static let collapsedFootprint: CGFloat = topPadding + collapsedHeight + bottomPadding
    /// Row 2 alone: what the Reader's text keeps clear, expanded or collapsed (the Reader has no row 1).
    static let row2Footprint: CGFloat = topPadding + row2Height + bottomPadding
}

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.footprint` high
/// whose bottom edge is just above the home indicator. Pure: the same state always gives the same
/// frames, so the widths in `width-table.md` are checkable without a screen, and it mirrors
/// `MC.layout` in the mockups.
///
/// ```
/// expanded    [‹ ›][ address / search                  ]        row 1 (52); the Reader has none
///             [ Reader | Library | Browser ][▶][⋯]              row 2 (56), every screen
/// collapsed   [‹ ›][ address ][▶][icon][⋯]                      one row (48); the Reader's field is its title chip
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
            // One row: every piece is `collapsedHeight` high, circles that wide.
            let d = M.collapsedHeight
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
            (back, forward) = Self.arrows(count: arrows, left: M.margin, top: rowTop, button: d, height: d)
            let left = M.margin + (arrows > 0 ? CGFloat(arrows) * d + M.gap : 0)
            field = CGRect(x: left, y: rowTop, width: max(0, right - left), height: d)
        case .two:
            let h2 = M.row2Height
            let row2 = bottom - h2
            if state.editing {
                editBar = CGRect(x: M.margin, y: row2, width: w - 2 * M.margin, height: h2)
            } else {
                let moreFrame = CGRect(x: w - M.margin - h2, y: row2, width: h2, height: h2)
                more = moreFrame
                var right = moreFrame.minX - M.gap
                if state.played {
                    let p = CGRect(x: right - h2, y: row2, width: h2, height: h2)
                    play = p
                    right = p.minX - M.gap
                }
                pill = CGRect(x: M.margin, y: row2, width: max(0, right - M.margin), height: h2)
            }

            if !isReader {
                let h1 = M.row1Height
                let row1 = row2 - M.gap - h1
                let arrows = isBrowse && (state.canGoBack || state.canGoForward) ? (state.canGoForward ? 2 : 1) : 0
                let navWidth = arrows == 2 ? M.navPairWidth : arrows == 1 ? M.navSingleWidth : 0
                (back, forward) = Self.arrows(count: arrows, left: M.margin, top: row1,
                                              button: navWidth / CGFloat(max(arrows, 1)), height: h1)
                let left = M.margin + (arrows > 0 ? navWidth + M.gap : 0)
                field = CGRect(x: left, y: row1, width: w - M.margin - left, height: h1)
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

    private static func arrows(count: Int, left: CGFloat, top: CGFloat, button: CGFloat, height: CGFloat) -> (CGRect?, CGRect?) {
        guard count > 0 else { return (nil, nil) }
        let back = CGRect(x: left, y: top, width: button, height: height)
        guard count > 1 else { return (back, nil) }
        return (back, CGRect(x: left + button, y: top, width: button, height: height))
    }
}
