import SwiftUI
import UIKit

/// A sheet's pull down, as a UIKit pan: a SwiftUI `DragGesture` on a parent never sees a drag that
/// starts on a child `Button`, `Menu` or tap area, so a header or card full of controls could not be
/// pulled. This pan begins only on a drag that has moved downward and mostly vertically from where
/// the finger came down; once it does, UIKit makes the controls under the finger fail (no tap on
/// release). A control that has already recognized (the scrubber's drag, from touch down) keeps the
/// touch, so scrubbing never pulls. A scroll view under the finger (the text) waits for it: a drag
/// down that may pull never scrolls first, and one that goes another way scrolls as usual. A tap
/// never moves, so it always reaches what is under it.
/// Positions are read in the window, which stays still while the sheet follows the finger.
struct SheetPullPan: UIGestureRecognizerRepresentable {
    /// Only a touch that comes down above this line (points from the window's top) can pull; one
    /// that comes down lower is left to the views under it. Infinity: anywhere on the view.
    var startsAbove: CGFloat = .infinity
    /// The vertical translation so far (down positive).
    let changed: (CGFloat) -> Void
    /// Let go: the translation and the vertical velocity (points per second).
    let ended: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        context.coordinator.startsAbove = startsAbove
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let window = pan.view?.window
        let translation = pan.translation(in: window).y
        switch pan.state {
        case .changed: changed(translation)
        case .ended: ended(translation, pan.velocity(in: window).y)
        case .cancelled, .failed: ended(0, 0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var startsAbove: CGFloat = .infinity
        /// Where the finger came down, in the window.
        private var touchDown: CGPoint?

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let point = touch.location(in: nil)
            guard point.y < startsAbove else { return false }
            touchDown = point
            return true
        }

        /// The direction from the touch down, not the pan's velocity at this instant, which a finger's
        /// last sample or two can turn sideways on a pull that went down.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let touchDown else { return false }
            let point = recognizer.location(in: nil)
            let moved = CGSize(width: point.x - touchDown.x, height: point.y - touchDown.y)
            return moved.height > 0 && SwipeGesturePolicy.axis(ofFirstMovement: moved) == .vertical
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

extension View {
    /// This view pulls its sheet down with `pan`; nil leaves it as it is.
    @ViewBuilder
    func pullHandle(_ pan: SheetPullPan?) -> some View {
        if let pan { gesture(pan) } else { self }
    }
}
