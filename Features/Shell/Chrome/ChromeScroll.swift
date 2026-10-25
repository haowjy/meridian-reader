import CoreGraphics
import Observation

/// Whether scrolling up re-expands the Reader's chrome. Off: the Reader's chrome stays collapsed
/// until the screen icon, the title chip, a swipe up on the row or the top of the text expands it.
/// Library and Browse always re-expand (`ChromeScroll.expandDistance`).
enum ReaderChromeScroll {
    static let scrollUpReexpands = false
}

/// The one scroll controller of the compact chrome, fed by the Library, the Browser and the Reader.
/// Scroll views report their offset; this turns it into a binary collapsed flag with hysteresis,
/// so a flick doesn't flutter: it collapses after `collapseDistance` of downward travel, expands
/// after `expandDistance` of upward travel (when the source lets scrolling up expand), and always
/// expands at the top.
@MainActor
@Observable
final class ChromeScroll {
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

    /// A scroll view's content offset, 0 at its top edge (below its own top inset). `upExpands`:
    /// scrolling up re-expands (the Reader passes `ReaderChromeScroll.scrollUpReexpands`).
    func scrolled(to offset: CGFloat, upExpands: Bool = true) {
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
        } else if !movingDown, upExpands, anchor - offset > Self.expandDistance {
            set(false)
        } else if movingDown == isScrolledDown {
            // Moving on in the direction the bar already took: keep the stroke's extreme as anchor.
            anchor = movingDown ? min(anchor, offset) : max(anchor, offset)
        }
    }

    /// The offset moved without a finger (a restore, following the audio, a scrub), or in a state
    /// where the finger decides nothing (full screen): the next report measures from here, and no
    /// collapse is decided by the move itself. The top still always expands (a status-bar tap).
    func anchor(at offset: CGFloat) {
        last = offset
        anchor = offset
        movingDown = true
        if offset <= 1 { set(false) }
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
