import SwiftUI

/// The app's motion vocabulary. Every animation uses one of these, so surfaces feel alike and
/// every animation can be interrupted and retargeted (springs, not fixed-duration curves).
///
/// Reduce Motion: anything that would move, slide, scale or blur only cross-fades instead
/// (`AnyTransition.slideAndFade(from:reduceMotion:)`, `.sheet(reduceMotion:)`, the ⋯ morph, a
/// committed pull-down). Gestures still follow the finger; that is direct manipulation, not
/// animation.
enum Motion {
    /// Surfaces: the sheets, the ⋯ menu morph, Now Playing following the audio.
    static let standard = Animation.spring(response: standardResponse, dampingFraction: 1 - standardBounce)
    /// `standard` as UIKit spring parameters (`UIView.animate(springDuration:bounce:)`), for what
    /// SwiftUI can't animate: a web view's scroll offset.
    static let standardResponse: TimeInterval = 0.35
    static let standardBounce: CGFloat = 0.14
    /// Small state changes: chrome, the scrub thumb, banners.
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.9)
    /// A drag released short of committing, springing back to rest.
    static let settle = Animation.spring(response: 0.3, dampingFraction: 0.85)

    /// A swipe-to-dismiss that committed: carries on at the finger's release speed instead of
    /// starting from rest. `velocity` is points per second toward the target; `distance` is how
    /// far the animated value still has to go.
    static func dismiss(velocity: CGFloat, distance: CGFloat) -> Animation {
        .interpolatingSpring(duration: 0.35, bounce: 0,
                             initialVelocity: releaseVelocity(velocity, over: distance))
    }

    /// A release speed as a spring's initial velocity: fractions of the remaining distance per
    /// second, at most `maxReleaseVelocity`. Movement away from the target, no distance left or a
    /// speed the touch system couldn't measure (NaN) seeds nothing. The cap keeps a flick (or an
    /// infinite speed from two touches with one timestamp) from overshooting wildly, or from
    /// giving the spring a velocity it can never settle from.
    static func releaseVelocity(_ velocity: CGFloat, over distance: CGFloat) -> Double {
        guard distance > 1, velocity > 0 else { return 0 }
        return min(Double(velocity / distance), maxReleaseVelocity)
    }

    /// Fastest release `dismiss(velocity:distance:)` honours: the whole distance in 1/8 s.
    static let maxReleaseVelocity = 8.0
}

extension AnyTransition {
    /// Slides in from (and out to) `edge` while fading; only fades under Reduce Motion.
    static func slideAndFade(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// A full-screen surface that rises from the bottom and leaves the same way, like a sheet (the
    /// reader overlay, so it closes along the axis its pull-down uses); only fades under Reduce
    /// Motion.
    static func sheet(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom)
    }
}
