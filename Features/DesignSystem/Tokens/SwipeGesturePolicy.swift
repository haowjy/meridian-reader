import SwiftUI

enum SwipeGestureDirection {
    case left
    case right
}

/// How the app's drags pick an axis and when a release commits: the sheets' and the ⋯ panel's
/// pull-down, the bottom band's pull that lowers the keyboard, the Now Playing bar's swipe up and
/// the listen controller's sideways swipe between paragraphs.
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

    /// Where a drag released at `velocity` (points per second) is heading, for a UIKit pan that
    /// has no predicted end of its own: a quarter second's travel at that speed. With the commit
    /// rule above, a pull from rest commits once flung at about 700 pt/s.
    static func projectedTranslation(_ translation: CGFloat, velocity: CGFloat) -> CGFloat {
        translation + velocity * releaseProjection
    }

    private static let releaseProjection: CGFloat = 0.25

    static func horizontalDirection(translation: CGSize, predicted: CGSize) -> SwipeGestureDirection? {
        guard abs(translation.width) > abs(translation.height) * axisDominance else { return nil }
        guard abs(translation.width) > horizontalCommitDistance
                || abs(predicted.width) > horizontalCommitPrediction else { return nil }
        return translation.width > 0 ? .right : .left
    }
}
