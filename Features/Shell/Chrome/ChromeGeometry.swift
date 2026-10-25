import CoreGraphics

/// The three places the chrome's pill switches between. The Reader is a destination: it keeps
/// the chrome (row 2 only) under the article, so `.reader` is the lit segment while the Reader or
/// Now Playing is up.
enum ChromeDestination: CaseIterable, Equatable {
    case reader, library, browse
}

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
enum ChromeMetrics {
    /// Left and right margin; also the gap between a row's pieces and the screen edge.
    static let margin: CGFloat = 12
    /// Gap between two pieces on a row, and between the rows.
    static let gap: CGFloat = 8
    /// The space above the top row and below the bottom row.
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 6

    /// Row 1 (expanded): the arrows, the address field, the Library search.
    static let row1Height: CGFloat = 52
    /// Row 2 (expanded): the pill, ▶, ⋯ and the edit bar.
    static let row2Height: CGFloat = 56
    /// The one row (collapsed or searching): every piece.
    static let collapsedHeight: CGFloat = 48
    /// ‹ alone is a circle; with › it is a capsule of two circles' width.
    static let navSingleWidth: CGFloat = row1Height
    static let navPairWidth: CGFloat = 2 * row1Height

    /// The narrowest address field before the arrows give way to it.
    static let minimumField: CGFloat = 120
    /// The pill's lit segment is inset from the pill's edge and from its neighbours by this much,
    /// on all four sides.
    static let litInset: CGFloat = 4

    /// What the chrome reserves at the bottom of a scrolling screen (expanded), above the safe
    /// area: the same on every destination, so a screen never resizes when the chrome collapses.
    static let footprint: CGFloat = topPadding + row1Height + gap + row2Height + bottomPadding
    /// One row high: what a screen keeps clear while the chrome is collapsed or searching.
    static let collapsedFootprint: CGFloat = topPadding + collapsedHeight + bottomPadding
    /// The Reader keeps only row 2: what its text keeps clear.
    static let readerFootprint: CGFloat = topPadding + row2Height + bottomPadding
}

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.footprint` high
/// whose bottom edge is just above the home indicator. Pure: the same inputs always give the same
/// frames, so the widths in `width-table.md` are checkable without a screen.
///
/// ```
/// expanded   [‹ ›][ address / search                  ]        row 1 (52)
///            [ Reader | Library | Browser ][▶][⋯]              row 2 (56)
/// reader     [ Reader | Library | Browser          ][⋯]        row 2 only
/// collapsed  [‹ ›][ address ][▶][icon][⋯]                      one row (48)
/// searching  [ field                    ][icon][✕]             one row
/// ```
struct ChromeGeometry: Equatable {
    struct Input: Equatable {
        var width: CGFloat
        var destination: ChromeDestination
        /// One row (scrolled down, or searching).
        var collapsed: Bool
        /// A search session is open in the field: one row, no arrows, ✕ in place of ⋯.
        var searching = false
        /// The browser has somewhere to go back to / forward to.
        var canGoBack = false
        var canGoForward = false
        /// The play/pause button is offered (something is bound or can be resumed).
        var hasPlay = false
    }

    /// The address or search field; nil on the Reader, which has none.
    var field: CGRect?
    /// The ‹ and › buttons, nil when dropped.
    var back: CGRect?
    var forward: CGRect?
    /// The pill (expanded only).
    var pill: CGRect?
    var play: CGRect?
    /// The current-screen icon (collapsed only).
    var icon: CGRect?
    /// ⋯, or ✕ while searching.
    var more: CGRect
    var isCollapsed: Bool

    var navigation: CGRect? { back.map { b in forward.map { b.union($0) } ?? b } }

    init(_ input: Input) {
        typealias M = ChromeMetrics
        let w = input.width
        let isReader = input.destination == .reader
        let one = (input.collapsed || input.searching) && !isReader
        isCollapsed = one
        let isBrowse = input.destination == .browse
        let bottom = M.footprint - M.bottomPadding

        if one {
            // One row: every piece is `collapsedHeight` high, circles that wide.
            let d = M.collapsedHeight
            let rowTop = bottom - d
            more = CGRect(x: w - M.margin - d, y: rowTop, width: d, height: d)
            icon = CGRect(x: more.minX - M.gap - d, y: rowTop, width: d, height: d)
            var right = (icon?.minX ?? 0) - M.gap
            if input.hasPlay, !input.searching {
                let p = CGRect(x: right - d, y: rowTop, width: d, height: d)
                play = p
                right = p.minX - M.gap
            } else {
                play = nil
            }
            pill = nil

            // The arrows: › goes first (always with a play button beside it), then ‹, as soon as the
            // address would fall under its minimum.
            var arrows = 0
            if isBrowse, !input.searching, input.canGoBack || input.canGoForward {
                arrows = input.canGoForward ? 2 : 1
                if input.hasPlay { arrows = min(arrows, 1) }
                while arrows > 0, right - (M.margin + CGFloat(arrows) * d + M.gap) < M.minimumField {
                    arrows -= 1
                }
            }
            (back, forward) = Self.arrows(count: arrows, left: M.margin, top: rowTop, button: d, height: d)
            let left = M.margin + (arrows > 0 ? CGFloat(arrows) * d + M.gap : 0)
            field = CGRect(x: left, y: rowTop, width: max(0, right - left), height: d)
        } else {
            let h2 = M.row2Height
            let row2 = bottom - h2
            more = CGRect(x: w - M.margin - h2, y: row2, width: h2, height: h2)
            var right = more.minX - M.gap
            if input.hasPlay, !isReader {
                let p = CGRect(x: right - h2, y: row2, width: h2, height: h2)
                play = p
                right = p.minX - M.gap
            } else {
                play = nil
            }
            pill = CGRect(x: M.margin, y: row2, width: max(0, right - M.margin), height: h2)
            icon = nil

            if isReader {
                field = nil
                back = nil
                forward = nil
            } else {
                let h1 = M.row1Height
                let row1 = row2 - M.gap - h1
                let arrows = isBrowse && (input.canGoBack || input.canGoForward) ? (input.canGoForward ? 2 : 1) : 0
                let navWidth = arrows == 2 ? M.navPairWidth : arrows == 1 ? M.navSingleWidth : 0
                (back, forward) = Self.arrows(count: arrows, left: M.margin, top: row1,
                                              button: navWidth / CGFloat(max(arrows, 1)), height: h1)
                let left = M.margin + (arrows > 0 ? navWidth + M.gap : 0)
                field = CGRect(x: left, y: row1, width: max(0, w - M.margin - left), height: h1)
            }
        }
    }

    private static func arrows(count: Int, left: CGFloat, top: CGFloat, button: CGFloat, height: CGFloat) -> (CGRect?, CGRect?) {
        guard count > 0 else { return (nil, nil) }
        let back = CGRect(x: left, y: top, width: button, height: height)
        guard count > 1 else { return (back, nil) }
        return (back, CGRect(x: left + button, y: top, width: button, height: height))
    }
}
