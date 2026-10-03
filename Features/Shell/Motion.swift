import SwiftUI

/// The app's motion vocabulary. Every animation uses one of these, so surfaces feel alike and
/// every animation can be interrupted and retargeted (springs, not fixed-duration curves).
///
/// Reduce Motion: anything that would move, slide, scale or blur only cross-fades instead
/// (`AnyTransition.slideAndFade(from:reduceMotion:)`, the ⋯ morph). Gestures still follow the
/// finger; that is direct manipulation, not animation.
enum Motion {
    /// Surfaces: the reader overlay, the ⋯ menu morph.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.86)
    /// Small state changes: chrome, the scrub thumb, banners.
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.9)
    /// A drag released short of committing, springing back to rest.
    static let settle = Animation.spring(response: 0.3, dampingFraction: 0.85)
}

extension AnyTransition {
    /// Slides in from (and out to) `edge` while fading; only fades under Reduce Motion.
    static func slideAndFade(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
