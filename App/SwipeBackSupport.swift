import SwiftUI
import UIKit

enum SwipeGestureDirection {
    case left
    case right
}

enum SwipeGesturePolicy {
    static let verticalMinimumDistance: CGFloat = 14
    static let horizontalMinimumDistance: CGFloat = 24

    private static let axisDominance: CGFloat = 1.35
    private static let verticalCommitDistance: CGFloat = 72
    private static let verticalCommitPrediction: CGFloat = 180
    private static let horizontalCommitDistance: CGFloat = 54
    private static let horizontalCommitPrediction: CGFloat = 140

    /// The axis a drag moves along, decided once from its first movement and kept for the rest of
    /// the gesture, so a drag that drifts diagonally never flips between following and not.
    static func axis(ofFirstMovement translation: CGSize) -> Axis {
        abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
    }

    /// Offset of a swipe-down-to-dismiss surface for a vertical drag: it follows the finger down
    /// and resists going up (rubber band), so the surface never jumps.
    static func dismissOffset(forVerticalTranslation t: CGFloat) -> CGFloat {
        t >= 0 ? t : -pow(-t, 0.7)
    }

    /// Release of a drag already locked to the vertical axis: far enough down, or flung down.
    static func shouldCommitDownwardDismiss(translation: CGFloat, predicted: CGFloat) -> Bool {
        translation > verticalCommitDistance || predicted > verticalCommitPrediction
    }

    static func horizontalDirection(translation: CGSize, predicted: CGSize) -> SwipeGestureDirection? {
        guard abs(translation.width) > abs(translation.height) * axisDominance else { return nil }
        guard abs(translation.width) > horizontalCommitDistance
                || abs(predicted.width) > horizontalCommitPrediction else { return nil }
        return translation.width > 0 ? .right : .left
    }
}

extension View {
    /// Edge swipe-back for a pushed screen that hides the system back button and draws its own
    /// back control (the library's reader). See `EdgeSwipeBack`.
    func edgeSwipeBack() -> some View {
        background(EdgeSwipeBack().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Swipe-back rule (docs/NAVIGATION.md): a pushed screen pops with a swipe from the left edge,
/// exactly like its back control. UIKit's edge pan refuses to begin once the back button is
/// hidden, so while a screen using `.edgeSwipeBack()` is on screen, this makes its navigation
/// controller's edge pan:
/// - begin only at depth > 1 and not while a push / pop is already running;
/// - stay the system gesture: it starts only at the left screen edge and a completed swipe is a
///   normal pop, the same as the back control (`onDisappear` runs, playback is untouched);
/// - win over scroll views (the reader's web view) at the very edge; anywhere else they scroll.
/// iOS 26's full-width content swipe is off meanwhile, so a sideways drag on the scrubber or a
/// text selection never pops the screen. Leaving the screen hands both gestures back as they were.
private struct EdgeSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {}

    /// Sits in the pushed screen's view controller hierarchy to reach its navigation controller.
    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        private weak var navigation: UINavigationController?
        private weak var systemDelegate: UIGestureRecognizerDelegate?
        private var contentPopWasEnabled = true

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            uninstall()
        }

        private func install() {
            guard let nav = navigationController, let edge = nav.interactivePopGestureRecognizer else { return }
            if edge.delegate !== self {
                systemDelegate = edge.delegate
                edge.delegate = self
            }
            if navigation !== nav, #available(iOS 26.0, *), let content = nav.interactiveContentPopGestureRecognizer {
                contentPopWasEnabled = content.isEnabled
                content.isEnabled = false
            }
            navigation = nav
        }

        private func uninstall() {
            guard let nav = navigation else { return }
            if let edge = nav.interactivePopGestureRecognizer, edge.delegate === self {
                edge.delegate = systemDelegate
            }
            if #available(iOS 26.0, *) {
                nav.interactiveContentPopGestureRecognizer?.isEnabled = contentPopWasEnabled
            }
            navigation = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let nav = navigation else { return false }
            return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.view is UIScrollView
        }
    }
}
