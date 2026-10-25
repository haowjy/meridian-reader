import SwiftUI
import UIKit

/// Inside a `Sheet`: how its scrolling body hands a pull to the sheet. A drag that begins with the
/// body at its top and keeps going down moves the sheet instead of bouncing the content, so the
/// sheet can be pulled down from anywhere on it, one-handed, like a system sheet. Outside a sheet
/// there is none, and the content scrolls and bounces as usual.
///
/// `changed` gets the sheet's offset (0 or more, following the finger 1:1); `ended` the offset
/// and the finger's speed at release (points per second, down positive), and the sheet commits or
/// springs back by the same rules as a pull on its header.
///
/// A reference the sheet keeps for its life: closures can't be compared, so a new value in the
/// environment on every pass of the sheet's body would update the content (a web view) each time.
@MainActor
final class SheetPullHandoff {
    var changed: (CGFloat) -> Void = { _ in }
    var ended: (_ offset: CGFloat, _ velocity: CGFloat) -> Void = { _, _ in }
}

extension EnvironmentValues {
    /// Set by `Sheet` on its content; nil elsewhere.
    @Entry var sheetPullHandoff: SheetPullHandoff? = nil
}

/// One drag on a sheet's scrolling body, as a pull hand-off (the rules, without UIKit):
/// - It can pull the sheet only if it began with the content at its top and moving vertically. A
///   drag that began mid-content only scrolls, even once the content reaches its top, so reading
///   back up an article never closes it.
/// - Then, with the content at its top, moving down pulls the sheet (the content held at its
///   top); moving back up lowers the pull first, and only once the sheet is back at rest does the
///   content scroll again.
struct SheetPullTracking: Equatable {
    /// This drag may pull the sheet.
    let canPull: Bool
    /// How far the sheet is pulled down.
    private(set) var pull: CGFloat = 0
    /// The content moved during this drag (not just the sheet).
    private(set) var scrolled = false

    /// `scrolledIn`: how far the content is scrolled from its top when the drag is recognised (0
    /// at the top, negative rubber-banded past it). `translation`: the finger's movement so far.
    init(scrolledIn: CGFloat, translation: CGSize, isInSheet: Bool) {
        // The scroll view has already moved the content by that first movement: a drag that
        // started at the top and went up is `-translation.height` into the content now. One that
        // went down from just below the top may have reached it: allowed, within the movement it
        // takes to recognise a drag.
        let start = min(scrolledIn, scrolledIn + translation.height)
        canPull = isInSheet
            && SwipeGesturePolicy.axis(ofFirstMovement: translation) == .vertical
            && start <= Self.topTolerance
        lastScrolledIn = max(0, start)
    }

    /// Where the content was after the last movement: what a movement down scrolls before it
    /// reaches the top.
    private var lastScrolledIn: CGFloat

    /// The finger moved `delta` down (negative: up); `scrolledIn` is where the content is after
    /// the scroll view's own handling of that movement. Returns whether the content must be held
    /// at its top (the sheet is pulled).
    mutating func move(by delta: CGFloat, scrolledIn: CGFloat) -> Bool {
        let atTop = scrolledIn <= Self.topTolerance
        if canPull {
            if pull > 0 {
                pull = max(0, pull + delta)
            } else if atTop, delta > 0 {
                // The part of the movement left once the content reached its top.
                pull = max(0, delta - lastScrolledIn)
            }
        }
        if pull == 0, !atTop { scrolled = true }
        lastScrolledIn = pull > 0 ? 0 : max(0, scrolledIn)
        return pull > 0
    }

    /// Half a point: a page at its top can sit a fraction off it.
    static let topTolerance: CGFloat = 0.5
}

/// Drives a `SheetPullHandoff` from a scroll view's own pan (a target on its recognizer, because
/// a web view's scroll view delegate belongs to WebKit). It runs after the scroll view's own
/// handling of each movement, so holding the content at its top undoes the bounce the scroll view
/// just applied. Finger positions are read in the window: the sheet, and the scroll view with it,
/// moves under the finger.
@MainActor
final class ScrollPullHandoff: NSObject {
    var handoff: SheetPullHandoff?
    /// The drag began (whether it scrolls or pulls).
    var onDragBegan: () -> Void = {}
    /// The drag moved the content, once per drag: a pull of the sheet alone doesn't call it.
    var onScroll: () -> Void = {}
    /// The drag ended without pulling the sheet, the finger's speed at release (points per
    /// second, down positive; 0 for a cancelled touch). Called after the scroll view has begun
    /// its own deceleration.
    var onRelease: (CGFloat) -> Void = { _ in }

    /// The drag in progress, and the sheet it may pull: taken when the drag begins, so a change
    /// of `handoff` meanwhile (full screen coming on) never strands a pull half-way.
    private var drag: (tracking: SheetPullTracking, handoff: SheetPullHandoff?)?
    private var lastY: CGFloat = 0
    private var reportedScroll = false

    /// The sheet is pulled by the drag in progress.
    var isPulling: Bool { (drag?.tracking.pull ?? 0) > 0 }

    /// The scroll view whose pan drives it.
    private(set) weak var scrollView: UIScrollView?

    func attach(to scrollView: UIScrollView) {
        detach()
        self.scrollView = scrollView
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
    }

    /// Stops listening; a pull in progress springs back, as a cancelled touch's does.
    func detach() {
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panned(_:)))
        scrollView = nil
        if isPulling { drag?.handoff?.ended(0, 0) }
        drag = nil
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let sv = pan.view as? UIScrollView else { return }
        let translation = pan.translation(in: nil)
        switch pan.state {
        case .began:
            drag = (SheetPullTracking(scrolledIn: scrolledIn(sv), translation: CGSize(
                width: translation.x, height: translation.y), isInSheet: handoff != nil), handoff)
            lastY = 0
            reportedScroll = false
            onDragBegan()
            move(sv, to: translation.y)
        case .changed:
            move(sv, to: translation.y)
        case .ended, .cancelled, .failed:
            release(sv, lifted: pan.state == .ended, velocity: pan.velocity(in: nil).y)
        default:
            break
        }
    }

    private func move(_ sv: UIScrollView, to y: CGFloat) {
        guard case (var t, let handoff)? = drag else { return }
        let before = t.pull
        let delta = y - lastY
        let holds = t.move(by: delta, scrolledIn: scrolledIn(sv))
        lastY = y
        drag = (t, handoff)
        if holds { hold(sv) }
        if t.pull != before { handoff?.changed(t.pull) }
        if t.scrolled, !reportedScroll {
            reportedScroll = true
            onScroll()
        }
    }

    /// `lifted`: the finger lifted (else the touch was cancelled, and the sheet springs back).
    private func release(_ sv: UIScrollView, lifted: Bool, velocity: CGFloat) {
        guard case let (t, handoff)? = drag else { return }
        drag = nil
        guard t.pull > 0 else { return onRelease(lifted ? velocity : 0) }
        // Stops the bounce the scroll view starts from a downward release at its top: the sheet
        // carries the movement on, the content stays put.
        hold(sv)
        sv.setContentOffset(sv.contentOffset, animated: false)
        if lifted {
            handoff?.ended(t.pull, velocity)
        } else {
            handoff?.ended(0, 0)
        }
    }

    private func hold(_ sv: UIScrollView) {
        let top = -sv.adjustedContentInset.top
        if sv.contentOffset.y != top { sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: top) }
    }

    private func scrolledIn(_ sv: UIScrollView) -> CGFloat {
        sv.contentOffset.y + sv.adjustedContentInset.top
    }
}

extension View {
    /// Hands `scrollView`'s pulls to the `Sheet` this view is in: a pull down that begins with
    /// the content at its top moves the sheet (`SheetPullHandoff`), one that begins mid-content
    /// only scrolls, as in the Reader and Now Playing. For a scroll view the sheet's body doesn't
    /// wire itself (Browse's web view, in Follow's chapter preview). Outside a sheet it does
    /// nothing.
    func handsPullToSheet(from scrollView: UIScrollView?) -> some View {
        background(SheetPullScrollHook(scrollView: scrollView))
    }
}

/// Drives a `ScrollPullHandoff` from `scrollView`'s pan while it is on screen.
private struct SheetPullScrollHook: UIViewRepresentable {
    weak var scrollView: UIScrollView?

    func makeCoordinator() -> ScrollPullHandoff { ScrollPullHandoff() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let pull = context.coordinator
        pull.handoff = context.environment.sheetPullHandoff
        if let scrollView, pull.scrollView !== scrollView { pull.attach(to: scrollView) }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ScrollPullHandoff) {
        coordinator.detach()
    }
}
