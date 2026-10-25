import CoreGraphics
import Observation

/// The one owner of the compact chrome's presence, and its scroll controller, fed by the Library, the Browser and the Reader.
/// Scroll views report their offset; this turns it into a binary collapsed flag with hysteresis,
/// so a flick doesn't flutter: it collapses after `collapseDistance` of downward travel, expands
/// after `expandDistance` of upward travel (when the source lets scrolling up expand), and always
/// expands at the top.
@MainActor
@Observable
final class ChromeScroll {
    /// Scrolled down: the chrome is one row.
    private(set) var isScrolledDown = false
    /// The Reader's full screen: the chrome is removed. Set only by the reading page's middle tap
    /// (`ReadingInPlace.fullScreen`); scrolling never touches it.
    private(set) var fullScreen = false

    /// How much of the chrome shows: the one place both flags live.
    var presence: ChromePresence { ChromePresence(collapsed: isScrolledDown, fullScreen: fullScreen) }

    /// Whether scrolling up re-expands the Reader's chrome. Off: it stays collapsed until the screen
    /// icon, the title chip, a swipe up on the row or the top of the text expands it. Library and
    /// Browse always re-expand (`expandDistance`).
    static let readerScrollUpReexpands = false

    static let collapseDistance: CGFloat = 24
    static let expandDistance: CGFloat = 12
    /// A jump bigger than this between two reports is a programmatic scroll (a page load, a
    /// scroll-to-top), not a finger, and restarts the count.
    private static let jump: CGFloat = 400

    /// A swipe up on the collapsed row expands it: a drag past `swipeStart` that travels
    /// `swipeDistance` up, more up than across.
    nonisolated static let swipeStart: CGFloat = 16
    nonisolated static let swipeDistance: CGFloat = 24
    nonisolated static func isSwipeUp(_ translation: CGSize) -> Bool {
        translation.height < -swipeDistance && abs(translation.height) > abs(translation.width)
    }

    @ObservationIgnored private var last: CGFloat = 0
    @ObservationIgnored private var anchor: CGFloat = 0
    @ObservationIgnored private var movingDown = true

    /// A scroll view's content offset, 0 at its top edge (below its own top inset). `upExpands`:
    /// scrolling up re-expands (the Reader passes `readerScrollUpReexpands`).
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

    func setFullScreen(_ on: Bool) {
        if fullScreen != on { fullScreen = on }
    }

    /// A different scroll view is now the one driving the chrome (a destination, a pushed screen):
    /// two rows, out of full screen.
    func reset() {
        setFullScreen(false)
        last = 0
        anchor = 0
        movingDown = true
        set(false)
    }

    private func set(_ value: Bool) {
        if isScrolledDown != value { isScrolledDown = value }
    }
}
