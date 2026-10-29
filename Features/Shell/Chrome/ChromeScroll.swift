import CoreGraphics
import Observation
import QuartzCore

/// The one owner of how far the compact chrome has folded, and its scroll controller, fed by the
/// Library, the Browser and the Reader alike. Scroll views report their offset; this keeps a
/// continuous `progress` (0 expanded, 1 collapsed) that follows the finger on the way down only:
/// `progress += dy / travel` for a scroll down, and a scroll up never gives a row back (decided:
/// the rows are too big to pop out on every reverse flick, and a button is what brings them
/// back). The chrome comes back by a tap on the capsule it folded into (it pins it expanded:
/// scrolling down does not fold it again until the top, a new screen or page), or the very top of the text (0 at the top). Once the
/// finger has been still for `settleDelay` a half-folded chrome finishes folding. It is the
/// mockups' `bindScroll` without its reverse follow, and
/// `displayed` is its per-frame smoothing: an exponential filter with a `smoothing` time constant,
/// stepped by a display link while it still has ground to cover. What is drawn follows `displayed`;
/// rules (`isCollapsed`, the swipe) read `progress`.
///
/// Full screen is not scroll's: it is set only by the reading page's middle tap
/// (`ReadingInPlace.fullScreen`), and scrolling never touches it.
@MainActor
@Observable
final class ChromeScroll {
    /// 0 expanded, 1 folded into the capsule, anywhere between while a finger is on the scroll view.
    private(set) var progress: CGFloat = 0
    /// `progress` as drawn: it chases `progress` a frame at a time (`smoothing`).
    private(set) var displayed: CGFloat = 0
    /// Past half: the chrome is a capsule. Its own property so a screen that only needs to know (the
    /// reading page's floating controls) is not redrawn by every step of `progress`.
    private(set) var isCollapsed = false
    /// `isCollapsed` as drawn: past half in `displayed`, so what keeps clear of the chrome (the web
    /// view's inset, the reading page's floating controls) moves with the chrome and not ahead of it.
    private(set) var isDrawnCollapsed = false
    /// The Reader's full screen: the chrome is removed.
    private(set) var fullScreen = false
    /// The keyboard or the ⋯ panel is up: scrolling moves nothing.
    var isLocked = false
    /// The user expanded it by hand (the capsule's tap): scrolling down does not
    /// fold it again, for that scroll or any later one, until the text is back at its top, a new screen
    /// or page is up, or the screen is left. The pin is what makes the tap win over the scroll.
    private(set) var isPinnedExpanded = false
    /// The destination keeps its chrome expanded whatever the scroll (Listen, a reader in Pages mode):
    /// scroll reports move nothing, and turning it on expands.
    var holdsExpanded = false {
        didSet { if holdsExpanded { expand() } }
    }

    /// Points of scrolling that fold the chrome all the way.
    static let travel: CGFloat = 90
    /// At or above this offset the chrome is expanded.
    static let topEdge: CGFloat = 4
    static let settleDelay: Duration = .milliseconds(150)
    /// Seconds for `displayed` to cover 63% of the way to `progress` (the mockups' `TAU.t`).
    static let smoothing: Double = 0.055
    /// A jump bigger than this between two reports is a programmatic scroll (a page load, a
    /// scroll-to-top), not a finger, and moves nothing.
    private static let jump: CGFloat = 400

    /// A swipe up on the keyboard's row lowers the keyboard: a drag past `swipeStart` that travels
    /// `swipeDistance` up, more up than across.
    nonisolated static let swipeStart: CGFloat = 16
    nonisolated static let swipeDistance: CGFloat = 24
    nonisolated static func isSwipeUp(_ translation: CGSize) -> Bool {
        translation.height < -swipeDistance && abs(translation.height) > abs(translation.width)
    }

    @ObservationIgnored private var last: CGFloat = 0
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0

    /// A scroll view's content offset, 0 at its top edge (below its own top inset).
    func scrolled(to offset: CGFloat) {
        let delta = offset - last
        last = offset
        guard !isLocked, !holdsExpanded, !fullScreen else { return }
        if offset <= Self.topEdge {
            settling?.cancel()
            isPinnedExpanded = false
            set(0)
            return
        }
        guard !isPinnedExpanded else { return }
        guard delta != 0, abs(delta) <= Self.jump else { return }
        guard delta > 0 else { return }
        set(min(1, progress + delta / Self.travel))
        scheduleSettle()
    }

    /// The offset moved without a finger (a restore, following the audio, a scrub), or in a state
    /// where the finger decides nothing (full screen): the next report measures from here, and no
    /// fold is decided by the move itself. The top still always expands (a status-bar tap).
    func anchor(at offset: CGFloat) {
        last = offset
        if offset <= Self.topEdge {
            isPinnedExpanded = false
            set(0)
        }
    }

    /// Finishes a fold the finger stopped partway through: scrolling only ever folds.
    func settle() {
        settling?.cancel()
        if progress > 0, progress < 1 { set(1) }
    }

    /// Back to two rows because a screen or page changed (a new screen, a page reader opening): scrolling
    /// folds it again from here, so this clears the pin.
    func expand() {
        settling?.cancel()
        isPinnedExpanded = false
        set(0)
    }

    /// Back to two rows by the user's hand (the capsule's tap): it stays,
    /// whatever the scroll does next (`isPinnedExpanded`). A momentum scroll already under way cannot
    /// fold it either.
    func expandByHand() {
        expand()
        isPinnedExpanded = true
    }

    func setFullScreen(_ on: Bool) {
        if fullScreen != on { fullScreen = on }
    }

    /// A different scroll view is now the one driving the chrome (a destination, a pushed screen):
    /// two rows, out of full screen.
    func reset() {
        setFullScreen(false)
        last = 0
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
        if displayed != value, ticker == nil { startSmoothing() }
    }

    private func startSmoothing() {
        lastFrame = CACurrentMediaTime()
        ticker = FrameTicker { [weak self] now in self?.step(now) }
    }

    /// One frame of the filter. Stops the link once `displayed` has arrived.
    private func step(_ now: CFTimeInterval) {
        let dt = min(0.05, now - lastFrame)
        lastFrame = now
        let next = displayed + (progress - displayed) * CGFloat(1 - exp(-dt / Self.smoothing))
        if abs(progress - next) < 0.0005 {
            displayed = progress
            drawnCollapsed(progress)
            ticker?.stop()
            ticker = nil
        } else {
            displayed = next
            drawnCollapsed(next)
        }
    }

    private func drawnCollapsed(_ value: CGFloat) {
        if isDrawnCollapsed != (value >= 0.5) { isDrawnCollapsed = value >= 0.5 }
    }
}

/// A display link that calls `tick` with each frame's time until `stop` (the link holds its target).
@MainActor
private final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let tick: (CFTimeInterval) -> Void

    init(tick: @escaping (CFTimeInterval) -> Void) {
        self.tick = tick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) { tick(link.timestamp) }

    func stop() {
        link?.invalidate()
        link = nil
    }
}
