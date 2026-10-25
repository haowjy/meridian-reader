import CoreGraphics
import Observation

/// The one owner of how far the compact chrome has folded, and its scroll controller, fed by the
/// Library, the Browser and the Reader alike. Scroll views report their offset; this keeps a
/// continuous `progress` (0 expanded, 1 collapsed) that follows the finger in both directions:
/// `progress += dy / travel`, 0 at the top, and once the finger has been still for `settleDelay`
/// it snaps to the end the last scroll was heading for. It is the mockups' `bindScroll`; the
/// smoothing the prototype does per frame (a 55 ms time constant) is the host animating
/// `progress` (`Motion.follow`).
///
/// Full screen is not scroll's: it is set only by the reading page's middle tap
/// (`ReadingInPlace.fullScreen`), and scrolling never touches it.
@MainActor
@Observable
final class ChromeScroll {
    /// 0 expanded, 1 collapsed, anywhere between while a finger is on the scroll view.
    private(set) var progress: CGFloat = 0
    /// Past half: the chrome is a row. Its own property so a screen that only needs to know (the
    /// reading page's floating controls) is not redrawn by every step of `progress`.
    private(set) var isCollapsed = false
    /// The Reader's full screen: the chrome is removed.
    private(set) var fullScreen = false
    /// The keyboard or the ⋯ panel is up: scrolling moves nothing.
    var isLocked = false

    /// Points of scrolling that fold the chrome all the way.
    static let travel: CGFloat = 90
    /// At or above this offset the chrome is expanded.
    static let topEdge: CGFloat = 4
    static let settleDelay: Duration = .milliseconds(150)
    /// A jump bigger than this between two reports is a programmatic scroll (a page load, a
    /// scroll-to-top), not a finger, and moves nothing.
    private static let jump: CGFloat = 400

    /// A swipe up on the collapsed row expands it: a drag past `swipeStart` that travels
    /// `swipeDistance` up, more up than across.
    nonisolated static let swipeStart: CGFloat = 16
    nonisolated static let swipeDistance: CGFloat = 24
    nonisolated static func isSwipeUp(_ translation: CGSize) -> Bool {
        translation.height < -swipeDistance && abs(translation.height) > abs(translation.width)
    }

    @ObservationIgnored private var last: CGFloat = 0
    @ObservationIgnored private var lastDelta: CGFloat = 0
    @ObservationIgnored private var settling: Task<Void, Never>?

    /// A scroll view's content offset, 0 at its top edge (below its own top inset).
    func scrolled(to offset: CGFloat) {
        let delta = offset - last
        last = offset
        guard !isLocked, !fullScreen else { return }
        if offset <= Self.topEdge {
            settling?.cancel()
            set(0)
            return
        }
        guard delta != 0, abs(delta) <= Self.jump else { return }
        lastDelta = delta
        set(min(1, max(0, progress + delta / Self.travel)))
        scheduleSettle()
    }

    /// The offset moved without a finger (a restore, following the audio, a scrub), or in a state
    /// where the finger decides nothing (full screen): the next report measures from here, and no
    /// fold is decided by the move itself. The top still always expands (a status-bar tap).
    func anchor(at offset: CGFloat) {
        last = offset
        if offset <= Self.topEdge { set(0) }
    }

    /// Snaps to the end the last scroll was heading for (down: collapsed, up: expanded).
    func settle() {
        settling?.cancel()
        if progress > 0, progress < 1 { set(lastDelta > 0 ? 1 : 0) }
    }

    /// Back to two rows: the icon's tap, a swipe up on the collapsed row, a new screen.
    func expand() {
        settling?.cancel()
        set(0)
    }

    func setFullScreen(_ on: Bool) {
        if fullScreen != on { fullScreen = on }
    }

    /// A different scroll view is now the one driving the chrome (a destination, a pushed screen):
    /// two rows, out of full screen.
    func reset() {
        setFullScreen(false)
        last = 0
        lastDelta = 0
        expand()
    }

    private func scheduleSettle() {
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    private func set(_ value: CGFloat) {
        if progress != value { progress = value }
        if isCollapsed != (value >= 0.5) { isCollapsed = value >= 0.5 }
    }
}
