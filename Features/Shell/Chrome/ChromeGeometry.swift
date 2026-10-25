import CoreGraphics

/// The three places the chrome's pill switches between. The Reader is a destination in the
/// design, but until it has its own screen (PR2) the pill's Reader segment opens what is playing
/// or was last played, and the lit segment is always the Library or the Browser.
enum ChromeDestination: CaseIterable, Equatable {
    case reader, library, browse
}

/// The compact bottom chrome's sizes, from the approved mockups (`width-table.md`). Everything
/// that sets a size reads from here; `ChromeGeometry` places the pieces with them.
enum ChromeMetrics {
    /// Left and right margin; also the gap between a row's pieces and the screen edge.
    static let margin: CGFloat = 12
    /// Gap between two pieces on a row, and between the rows.
    static let gap: CGFloat = 8
    /// The space above the top row and below the bottom row.
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 6

    // Expanded
    /// The pill and ⋯ on row 2, and the row 1 slot (the field or the Library's search).
    static let rowHeight: CGFloat = 56
    static let browseFieldHeight: CGFloat = 52
    static let libraryFieldHeight: CGFloat = 56
    static let navHeight: CGFloat = 48
    /// The arrows' capsule: 92 wide with both, 48 with ‹ alone.
    static let navPairWidth: CGFloat = 92
    static let navSingleWidth: CGFloat = 48
    static let moreExpanded: CGFloat = 56

    // Collapsed: one row of 48
    static let collapsedRowHeight: CGFloat = 48
    static let collapsedFieldHeight: CGFloat = 48
    static let collapsedNavHeight: CGFloat = 44
    static let collapsedNavButtonWidth: CGFloat = 44
    static let moreCollapsed: CGFloat = 48
    /// The collapsed current-screen icon, and the play/pause button.
    static let iconSize: CGFloat = 44
    static let playSize: CGFloat = 44

    /// The narrowest address field before the arrows give way to it.
    static let minimumField: CGFloat = 120
    /// The pill's lit segment is inset from its segment: 1 pt each side, 4 pt top and bottom.
    static let litInsetX: CGFloat = 1
    static let litInsetY: CGFloat = 4

    /// What the chrome reserves at the bottom of a scrolling screen (expanded), above the safe
    /// area: the same on every destination, so a screen never resizes when the chrome collapses.
    static let footprint: CGFloat = topPadding + rowHeight + gap + rowHeight + bottomPadding
    /// One row high: what a screen keeps clear while the chrome is collapsed or searching.
    static let collapsedFootprint: CGFloat = topPadding + collapsedRowHeight + bottomPadding
}

/// Where each piece of the chrome sits, in a box `width` wide and `ChromeMetrics.footprint` high
/// whose bottom edge is just above the home indicator. Pure: the same inputs always give the same
/// frames, so the widths in `width-table.md` are checkable without a screen.
///
/// ```
/// expanded   [‹ ›][ address / search                  ]        row 1
///            [ Reader | Library | Browser ][▶][⋯]              row 2
/// collapsed  [‹ ›][ address ][▶][icon][⋯]                      one row
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

    var field: CGRect
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
        let one = input.collapsed || input.searching
        isCollapsed = one
        let isBrowse = input.destination == .browse
        let bottom = M.footprint - M.bottomPadding

        if one {
            let rowTop = bottom - M.collapsedRowHeight
            more = CGRect(x: w - M.margin - M.moreCollapsed, y: rowTop, width: M.moreCollapsed, height: M.moreCollapsed)
            let iconRect = CGRect(x: more.minX - M.gap - M.iconSize, y: rowTop + (M.collapsedRowHeight - M.iconSize) / 2,
                                  width: M.iconSize, height: M.iconSize)
            icon = iconRect
            var right = iconRect.minX - M.gap
            if input.hasPlay, !input.searching {
                let p = CGRect(x: right - M.playSize, y: rowTop + (M.collapsedRowHeight - M.playSize) / 2,
                               width: M.playSize, height: M.playSize)
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
                while arrows > 0, right - (M.margin + CGFloat(arrows) * M.collapsedNavButtonWidth + M.gap) < M.minimumField {
                    arrows -= 1
                }
            }
            let navTop = rowTop + (M.collapsedRowHeight - M.collapsedNavHeight) / 2
            (back, forward) = Self.arrows(count: arrows, left: M.margin, top: navTop,
                                          button: M.collapsedNavButtonWidth, height: M.collapsedNavHeight)
            let left = M.margin + (arrows > 0 ? CGFloat(arrows) * M.collapsedNavButtonWidth + M.gap : 0)
            field = CGRect(x: left, y: rowTop, width: max(0, right - left), height: M.collapsedFieldHeight)
        } else {
            let row2 = bottom - M.rowHeight
            more = CGRect(x: w - M.margin - M.moreExpanded, y: row2, width: M.moreExpanded, height: M.moreExpanded)
            var right = more.minX - M.gap
            if input.hasPlay {
                let p = CGRect(x: right - M.playSize, y: row2 + (M.rowHeight - M.playSize) / 2,
                               width: M.playSize, height: M.playSize)
                play = p
                right = p.minX - M.gap
            } else {
                play = nil
            }
            pill = CGRect(x: M.margin, y: row2, width: max(0, right - M.margin), height: M.rowHeight)
            icon = nil

            let row1 = row2 - M.gap - M.rowHeight
            let arrows = isBrowse && (input.canGoBack || input.canGoForward) ? (input.canGoForward ? 2 : 1) : 0
            let navTop = row1 + (M.rowHeight - M.navHeight) / 2
            let navWidth = arrows == 2 ? M.navPairWidth : arrows == 1 ? M.navSingleWidth : 0
            (back, forward) = Self.arrows(count: arrows, left: M.margin, top: navTop,
                                          button: navWidth / CGFloat(max(arrows, 1)), height: M.navHeight)
            let left = M.margin + (arrows > 0 ? navWidth + M.gap : 0)
            let height = isBrowse ? M.browseFieldHeight : M.libraryFieldHeight
            field = CGRect(x: left, y: row1 + (M.rowHeight - height) / 2, width: max(0, w - M.margin - left), height: height)
        }
    }

    private static func arrows(count: Int, left: CGFloat, top: CGFloat, button: CGFloat, height: CGFloat) -> (CGRect?, CGRect?) {
        guard count > 0 else { return (nil, nil) }
        let back = CGRect(x: left, y: top, width: button, height: height)
        guard count > 1 else { return (back, nil) }
        return (back, CGRect(x: left + button, y: top, width: button, height: height))
    }
}
