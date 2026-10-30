import CoreGraphics
import Observation
import QuartzCore

/// The one owner of how far the compact chrome has folded, and its scroll controller, fed by the
/// Library, the Browser and the Reader alike. Scroll views report their offset; this keeps a
/// continuous `progress` (0 expanded, 1 collapsed) that follows the finger on the way down only:
/// `progress += dy / travel` for a scroll down, and a scroll up never gives a row back (decided:
/// the rows are too big to pop out on every reverse flick, and a button is what brings them
/// back). It folds in two steps: 0 to 0.5 takes row 2 away (one row left), 0.5 to 1 takes the
/// field into the domain strip. The chrome comes back by a tap on the strip (the next `refoldGrace`
/// of scrolling down is ignored, then it folds again: no pin), the very top of the text (0 at the
/// top), a new page or screen, and opening the search. Once the finger has been still for
/// `settleDelay` a fold between steps finishes the step it is in. It is the
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
    /// 0 two rows, 0.5 one row, 1 the strip, anywhere between while a finger is on the scroll view.
    private(set) var progress: CGFloat = 0
    /// `progress` as drawn: it chases `progress` a frame at a time (`smoothing`).
    private(set) var displayed: CGFloat = 0
    /// Past the first step: row 2 is gone (one row or the strip). Its own property so a screen that only needs to know (the
    /// reading page's floating controls) is not redrawn by every step of `progress`.
    private(set) var isCollapsed = false
    /// `isCollapsed` as drawn: past half in `displayed`, so what keeps clear of the chrome (the web
    /// view's inset, the reading page's floating controls) moves with the chrome and not ahead of it.
    private(set) var isDrawnCollapsed = false
    /// The Reader's full screen: the chrome is removed.
    private(set) var fullScreen = false
    /// The keyboard or the ⋯ panel is up: scrolling moves nothing.
    var isLocked = false
    /// What is drawn, by step: 0 two rows, 1 one row, 2 the strip (nearest end of `displayed`), so
    /// what keeps clear of the chrome moves a step at a time with it (`ChromeMetrics.footprint(step:)`).
    private(set) var drawnStep = 0
    /// Points of scrolling down still ignored after the strip's tap: the rows stay for a short
    /// scroll (and the tail of a fling already under way), then fold again. Never a lasting pin.
    private(set) var grace: CGFloat = 0
    /// The destination keeps its chrome expanded whatever the scroll (Listen, a reader in Pages mode):
    /// scroll reports move nothing, and turning it on expands.
    var holdsExpanded = false {
        didSet { if holdsExpanded { expand() } }
    }

    /// Points of scrolling that fold the chrome all the way.
    static let travel: CGFloat = 120
    /// Scrolling down after the strip's tap brought the rows back that folds nothing.
    static let refoldGrace: CGFloat = 24
    /// After the strip's tap, scroll reports this soon are a fling already under way and move nothing.
    static let tapQuiet: CFTimeInterval = 0.35
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
    @ObservationIgnored private var tappedAt: CFTimeInterval = -1

    /// A scroll view's content offset, 0 at its top edge (below its own top inset).
    func scrolled(to offset: CGFloat) {
        let delta = offset - last
        last = offset
        guard !isLocked, !holdsExpanded, !fullScreen else { return }
        if offset <= Self.topEdge {
            settling?.cancel()
            grace = 0
            set(0)
            return
        }
        guard delta != 0, abs(delta) <= Self.jump else { return }
        guard delta > 0 else { return }
        var down = delta
        if grace > 0 {
            guard CACurrentMediaTime() - tappedAt >= Self.tapQuiet else { return }
            let used = min(grace, down)
            grace -= used
            down -= used
            guard down > 0 else { return }
        }
        set(min(1, progress + down / Self.travel))
        scheduleSettle()
    }

    /// The offset moved without a finger (a restore, following the audio, a scrub), or in a state
    /// where the finger decides nothing (full screen): the next report measures from here, and no
    /// fold is decided by the move itself. The top still always expands (a status-bar tap).
    func anchor(at offset: CGFloat) {
        last = offset
        if offset <= Self.topEdge {
            grace = 0
            set(0)
        }
    }

    /// Finishes the step the finger stopped partway through: scrolling only ever folds.
    func settle() {
        settling?.cancel()
        set(Self.stepEnd(progress))
    }

    /// The end of the step `progress` is in: 0, 0.5 or 1.
    nonisolated static func stepEnd(_ progress: CGFloat) -> CGFloat {
        progress <= 0 ? 0 : progress <= 0.5 ? 0.5 : 1
    }

    /// The step `value` is nearest: 0 two rows, 1 one row, 2 the strip.
    nonisolated static func step(_ value: CGFloat) -> Int { value < 0.25 ? 0 : value < 0.75 ? 1 : 2 }

    /// Back to two rows because a screen or page changed (a new screen, a page reader opening): scrolling
    /// folds it again from here.
    func expand() {
        settling?.cancel()
        grace = 0
        set(0)
    }

    /// Back to two rows by the user's hand (the strip's tap): they stay for the next `refoldGrace` of
    /// scrolling down (a fling already under way moves nothing for `tapQuiet`), then fold again.
    func expandByHand() {
        expand()
        grace = Self.refoldGrace
        tappedAt = CACurrentMediaTime()
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
        let step = Self.step(value)
        if drawnStep != step { drawnStep = step }
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
