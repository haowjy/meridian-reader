import SwiftUI
import UIKit

/// A sheet's pull down, as a UIKit pan: a SwiftUI `DragGesture` on a parent never sees a drag that
/// starts on a child `Button`, `Menu` or tap area, so a header or card full of controls could not be
/// pulled. This pan begins only on a drag that starts downward and mostly vertical; once it does,
/// UIKit makes the controls under the finger fail (no tap on release). A control that has already
/// recognized (the scrubber's drag, from touch down) keeps the touch, so scrubbing never pulls.
/// Translations are read in the window, which stays still while the sheet follows the finger.
struct SheetPullPan: UIGestureRecognizerRepresentable {
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
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view?.window)
            return v.y > 0 && SwipeGesturePolicy.axis(ofFirstMovement: CGSize(width: v.x, height: v.y)) == .vertical
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
