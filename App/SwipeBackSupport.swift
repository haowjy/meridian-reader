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

    static func verticalOffset(for translation: CGSize) -> CGFloat {
        guard translation.height > 0,
              translation.height > abs(translation.width) * axisDominance else { return 0 }
        return translation.height
    }

    static func shouldCommitVerticalDismiss(translation: CGSize, predicted: CGSize) -> Bool {
        guard translation.height > 0,
              translation.height > abs(translation.width) * axisDominance else { return false }
        return translation.height > verticalCommitDistance
            || predicted.height > verticalCommitPrediction
    }

    static func horizontalDirection(translation: CGSize, predicted: CGSize) -> SwipeGestureDirection? {
        guard abs(translation.width) > abs(translation.height) * axisDominance else { return nil }
        guard abs(translation.width) > horizontalCommitDistance
                || abs(predicted.width) > horizontalCommitPrediction else { return nil }
        return translation.width > 0 ? .right : .left
    }
}

/// App-wide swipe-back rule (see `docs/NAVIGATION.md`): every pushed screen can be popped by
/// swiping from the left edge, even when it hides the system back button / navigation bar and
/// draws its own ‹ (e.g. the Saved reader uses `.toolbar(.hidden, for: .navigationBar)`).
///
/// UIKit's default pop-gesture delegate refuses to begin when the bar or back button is hidden,
/// so SwiftUI screens with a custom ‹ lose swipe-back. Here every navigation controller
/// (SwiftUI's `NavigationStack` is backed by one) becomes its own pop-gesture delegate:
/// - begins only at depth > 1 (never on a root screen, which would wedge the stack), and not
///   while a push/pop transition is already running;
/// - it is still the system edge-pan gesture, so it only starts from the left screen edge and a
///   completed swipe is a normal pop — the same as tapping ‹ (`onDisappear` runs, playback
///   is untouched);
/// - scroll views (the reader's web view) wait for the edge pan to fail, so a horizontal
///   swipe from the very edge pops instead of scrolling; anywhere else scrolling is unchanged.
///
/// Do not add per-screen swipe-back hacks; push screens with `NavigationStack` and this applies.
///
/// Note: `UINavigationController` does not implement `viewDidLoad` itself (it only implements
/// `loadView` / `viewWillAppear:` / `viewDidAppear:`), so this override adds behavior without
/// replacing any UIKit implementation. `super` reaches `UIViewController.viewDidLoad`.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer, viewControllers.count > 1 else { return false }
        return otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.view is UIScrollView
    }
}
