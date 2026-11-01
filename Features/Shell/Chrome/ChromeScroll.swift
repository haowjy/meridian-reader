import CoreGraphics
import Observation
import QuartzCore

/// What scrolling does to the compact chrome on the screen showing (picked by `ChromeHost`).
enum ChromePolicy: Equatable {
    /// Web pages, the Library, Settings: the continuous fold to the bubble.
    case folds
    /// The start page, Library Edit, VoiceOver off a reader: two rows, whatever the scroll.
    case holds
    /// An in-place reader: expanded or full screen, nothing between. `scrollHides`: Scroll mode
    /// without VoiceOver; Pages and VoiceOver toggle by the centre tap alone.
    case reads(scrollHides: Bool)
}

/// A surface that can drive the compact chrome by scrolling. Only the one showing does
/// (`ChromeScroll.driver`); a new surface that scrolls needs a case here and a branch in
/// `ShellState.chromeDriver`, or its reports are dropped.
enum ChromeSource: Equatable {
    /// The Browser's web page or start page.
    case browser
    /// The Browser's reader mode, in place.
    case browserReader
    /// The Library's screens.
    case library
    /// Library Read, in place.
    case libraryReader
    /// Settings in place.
    case settings
}

/// The one owner of the compact chrome's visibility, and its scroll controller, fed by the Library,
/// the Browser, Settings and the in-place readers alike. What scrolling does is the `policy`.
///
/// **Folds** (web pages, the Library, Settings). Scroll views report their offset; this keeps a
/// continuous `progress` (0 expanded, 1 collapsed) that follows the finger on the way down only:
/// `progress += dy / travel` for a scroll down; a scroll up of `revealDistance` brings both rows back
/// at once, as Safari does (the owner's call). It folds in two steps: 0 to 0.5 takes row 2 away (one row left), 0.5 to 1 shrinks the
/// field into the bubble. The chrome comes back by a tap on the bubble (the next `refoldGrace`
/// of scrolling down is ignored, then it folds again: no pin), the very top of the text (0 at the
/// top), a scroll up, a new page or screen, and opening the search. Once the finger has been still for
/// `settleDelay` a fold between steps finishes the step it is in. It is the
/// mockups' `bindScroll` with a reveal in place of its reverse follow, and
/// `displayed` is its per-frame smoothing: an exponential filter with a `smoothing` time constant,
/// stepped by a display link while it still has ground to cover. What is drawn follows `displayed`;
/// rules (the swipe) read `progress`.
///
/// **Reads** (an in-place reader): `fullScreen` alone, no fold. In Scroll mode one gesture's
/// `fullScreenDistance` of scrolling down enters full screen and a scroll up of `revealDistance` leaves
/// it, however it began (the centre tap's toggle is the other way in and out, through
/// `ReadingInPlace.fullScreen`). Hiding travel is measured on the offset clamped at the top, so the
/// rebound from a pull past the top never hides; the pull itself counts toward a reveal. A move
/// (`anchor`) never toggles. Pages mode and VoiceOver toggle by the tap alone.
///
/// Every report names its source, and only the driver's counts (`driver`, checked when the report is
/// delivered: a web view's report queued before a reader opened is judged against the reader).
/// Every change of the driver (`drive`), suspension under Listen or a sheet included, drops the
/// gesture's continuity at once: the next accepted report only sets the baseline, so travel from
/// before never counts.
@MainActor
@Observable
final class ChromeScroll {
    /// 0 two rows, 0.5 one row, 1 the bubble, anywhere between while a finger is on the scroll view.
    private(set) var progress: CGFloat = 0
    /// `progress` as drawn: it chases `progress` a frame at a time (`smoothing`).
    private(set) var displayed: CGFloat = 0
    /// An in-place reader's full screen: the chrome, the reader's top group and the status bar are
    /// gone. False unless the policy is `.reads`.
    private(set) var fullScreen = false
    /// The keyboard or the ⋯ panel is up: scrolling moves nothing.
    var isLocked = false
    /// What is drawn, by step: 0 two rows, 1 one row, 2 the bubble (nearest end of `displayed`), so
    /// what keeps clear of the chrome moves a step at a time with it (`ChromeMetrics.clearance(step:home:)`).
    private(set) var drawnStep = 0
    /// Points of scrolling down still ignored after the bubble's tap: the rows stay for a short
    /// scroll (and the tail of a fling already under way), then fold again. Never a lasting pin.
    private(set) var grace: CGFloat = 0
    /// What scrolling does on the screen showing. Anything but `.folds` unfolds; anything but `.reads`
    /// leaves full screen. `.reads(true)` and `.reads(false)` share the full screen.
    var policy: ChromePolicy = .folds {
        didSet {
            guard policy != oldValue else { return }
            if policy != .folds { expand() }
            if case .reads = policy {} else { setFullScreen(false) }
            clearReading()
            #if DEBUG
            if policy == .folds, Self.forcedFold != nil { set(0) }
            #endif
        }
    }

    /// The surface whose reports count; nil: none (Listen or a sheet is up). Set by `ShellState`
    /// through `drive` on every change of what it shows.
    @ObservationIgnored private(set) var driver: ChromeSource?

    #if DEBUG
    /// `-chromeFold`: every fold is this one, where the chrome folds (`.folds`). Set by the launch (`AppMain`).
    static var forcedFold: CGFloat?
    #endif

    /// Points of scrolling that fold the chrome all the way.
    static let travel: CGFloat = 120
    /// Points of scrolling up, with no scroll down between, that bring the rows back (and leave a
    /// reader's full screen).
    static let revealDistance: CGFloat = 24
    /// Points of scrolling down in one gesture that take a reader to full screen: the moment a page's
    /// row 2 goes, about two and a half lines, so adjusting a line or two never hides the chrome.
    static let fullScreenDistance: CGFloat = travel / 2
    /// Scrolling down after the bubble's tap brought the rows back that folds nothing.
    static let refoldGrace: CGFloat = 24
    /// After the bubble's tap, scroll reports this soon are a fling already under way and move nothing.
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
    /// The source of the last accepted report; nil once the driver changed or was suspended, so the
    /// next accepted report starts a fresh baseline.
    @ObservationIgnored private var continuity: ChromeSource?
    /// Points scrolled up since the last scroll down.
    @ObservationIgnored private var upward: CGFloat = 0
    /// A reader's points scrolled down in this gesture, less what came back up.
    @ObservationIgnored private var downward: CGFloat = 0
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0
    @ObservationIgnored private var tappedAt: CFTimeInterval = -1

    /// A scroll view's content offset, 0 at its top edge (below its own top inset), from `source`.
    func scrolled(to offset: CGFloat, from source: ChromeSource) {
        guard accepts(source, at: offset) else { return }
        let previous = last
        last = offset
        guard !isLocked else { return }
        switch policy {
        case .folds: fold(to: offset, from: previous)
        case .reads(scrollHides: true): read(to: offset, from: previous)
        case .holds, .reads(scrollHides: false): break
        }
    }

    /// The fold's rule: down folds with the finger, `revealDistance` up expands, the top expands.
    private func fold(to offset: CGFloat, from previous: CGFloat) {
        let delta = offset - previous
        if offset <= Self.topEdge {
            settling?.cancel()
            grace = 0
            set(0)
            return
        }
        guard delta != 0, abs(delta) <= Self.jump else { return }
        guard delta > 0 else {
            upward -= delta
            if upward >= Self.revealDistance, progress > 0 { expand() }
            return
        }
        upward = 0
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

    /// The reading rule: `fullScreenDistance` down (clamped at the top) enters full screen,
    /// `revealDistance` up (raw, so a pull past the top counts) leaves it.
    private func read(to offset: CGFloat, from previous: CGFloat) {
        let delta = offset - previous
        guard delta != 0, abs(delta) <= Self.jump else { return }
        if delta > 0 {
            downward += max(0, offset) - max(0, previous)
            upward = 0
            if !fullScreen, downward >= Self.fullScreenDistance { setFullScreen(true) }
        } else {
            upward -= delta
            downward = max(0, downward + delta)
            if fullScreen, upward >= Self.revealDistance { setFullScreen(false) }
        }
    }

    /// The offset moved without a finger (a restore, following the audio, a scrub, a reflow) or a
    /// gesture begins: the next report measures from here, and the move itself decides nothing. On a
    /// folding screen the top still expands (a status-bar tap); a reader never toggles on a move.
    func anchor(at offset: CGFloat, from source: ChromeSource) {
        guard driver == source else { return }
        continuity = source
        last = offset
        switch policy {
        case .folds:
            if offset <= Self.topEdge {
                grace = 0
                set(0)
            }
        case .reads: clearReading()
        case .holds: break
        }
    }

    /// Finishes the step the finger stopped partway through.
    func settle() {
        settling?.cancel()
        set(Self.stepEnd(progress))
    }

    /// The end of the step `progress` is in: 0, 0.5 or 1.
    nonisolated static func stepEnd(_ progress: CGFloat) -> CGFloat {
        progress <= 0 ? 0 : progress <= 0.5 ? 0.5 : 1
    }

    /// The step `value` is nearest: 0 two rows, 1 one row, 2 the bubble.
    nonisolated static func step(_ value: CGFloat) -> Int { value < 0.25 ? 0 : value < 0.75 ? 1 : 2 }

    /// Back to two rows because a screen or page changed (a new screen, a page reader opening): scrolling
    /// folds it again from here.
    func expand() {
        settling?.cancel()
        grace = 0
        clearReading()
        set(0)
    }

    /// Back to two rows by the user's hand (the bubble's tap): they stay for the next `refoldGrace` of
    /// scrolling down (a fling already under way moves nothing for `tapQuiet`), then fold again.
    func expandByHand() {
        expand()
        grace = Self.refoldGrace
        tappedAt = CACurrentMediaTime()
    }

    /// A reader's full screen, by the centre tap (through the binding) or the reading rule. Each
    /// change starts the travel afresh: re-hiding after a reveal takes a full `fullScreenDistance`.
    func setFullScreen(_ on: Bool) {
        guard fullScreen != on else { return }
        fullScreen = on
        clearReading()
    }

    /// A different scroll view is now the one driving the chrome (a destination, a pushed screen):
    /// two rows, out of full screen.
    func reset() {
        setFullScreen(false)
        last = 0
        expand()
    }

    /// Whether a finger report from `source` moves anything: only the driver's, and the first after
    /// continuity was dropped just sets the baseline.
    private func accepts(_ source: ChromeSource, at offset: CGFloat) -> Bool {
        guard driver == source else { return false }
        guard continuity == source else {
            continuity = source
            last = offset
            upward = 0
            downward = 0
            return false
        }
        return true
    }

    /// `source` drives the chrome from now (nil: nothing, under Listen or a sheet). A change drops
    /// continuity at once, keeping what is drawn, so no change between two reports goes unseen.
    func drive(_ source: ChromeSource?) {
        guard source != driver else { return }
        driver = source
        continuity = nil
    }

    private func clearReading() {
        upward = 0
        downward = 0
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
        #if DEBUG
        let value = Self.forcedFold.map { policy == .folds ? $0 : 0 } ?? value
        #endif
        if progress != value { progress = value }
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
            draw(progress)
            ticker?.stop()
            ticker = nil
        } else {
            displayed = next
            draw(next)
        }
    }

    private func draw(_ value: CGFloat) {
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
