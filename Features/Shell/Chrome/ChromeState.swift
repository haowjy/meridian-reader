import CoreGraphics
import Observation

/// Whether the compact chrome is expanded (two rows) or scrolled down to one. Scroll views report
/// their offset; this turns it into a binary state with hysteresis, so a flick doesn't flutter
/// between the two: it collapses after `collapseDistance` of downward travel, expands after
/// `expandDistance` of upward travel, and always expands at the top.
@MainActor
@Observable
final class ChromeState {
    /// Scrolled down: the chrome is one row.
    private(set) var isScrolledDown = false

    static let collapseDistance: CGFloat = 24
    static let expandDistance: CGFloat = 12
    /// A jump bigger than this between two reports is a programmatic scroll (a page load, a
    /// scroll-to-top), not a finger, and restarts the count.
    private static let jump: CGFloat = 400

    @ObservationIgnored private var last: CGFloat = 0
    @ObservationIgnored private var anchor: CGFloat = 0
    @ObservationIgnored private var movingDown = true

    /// A scroll view's content offset, 0 at its top edge (below its own top inset).
    func scrolled(to offset: CGFloat) {
        let delta = offset - last
        last = offset
        if offset <= 1 {
            anchor = offset
            set(false)
            return
        }
        guard delta != 0 else { return }
        if abs(delta) > Self.jump {
            anchor = offset
            return
        }
        if (delta > 0) != movingDown {
            movingDown = delta > 0
            anchor = offset - delta
        }
        if movingDown, offset - anchor > Self.collapseDistance {
            set(true)
        } else if !movingDown, anchor - offset > Self.expandDistance {
            set(false)
        } else if movingDown == isScrolledDown {
            // Moving on in the direction the bar already took: keep the stroke's extreme as anchor.
            anchor = movingDown ? min(anchor, offset) : max(anchor, offset)
        }
    }

    /// Back to two rows: the icon's tap, a swipe up on the collapsed row, a new screen.
    func expand() {
        anchor = last
        set(false)
    }

    /// A different scroll view is now the one driving the chrome (a destination, a pushed screen).
    func reset() {
        last = 0
        anchor = 0
        movingDown = true
        set(false)
    }

    private func set(_ value: Bool) {
        if isScrolledDown != value { isScrolledDown = value }
    }
}
