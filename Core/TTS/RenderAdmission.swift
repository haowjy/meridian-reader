import Foundation

/// May an on-device model call start now? One rule for the render queue and the renderer.
///
/// | App phase | Route renders in background (ONNX CPU) | Core ML route |
/// |---|---|---|
/// | active | render | render |
/// | inactive | render | listener's chunks only; bake-ahead parks |
/// | background | listener's chunks; bake-ahead of the playing article during a burst (`BackgroundRenderWatermarks`); other articles park | no model call: a listener's chunk goes to Apple, bake-ahead parks |
///
/// Thermal / Low Power Mode holds on bake-ahead are separate (`BakeConditions`).
enum RenderAdmission: Equatable {
    /// Start the call.
    case render
    /// Not now: wait until the app is active again (or a listener asks).
    case park
    /// Not now, and a listener is waiting: the player speaks this audio with Apple instead.
    case deferToApple

    /// - Parameters:
    ///   - rendersInBackground: the active host keeps rendering while backgrounded (no Core ML).
    ///   - isLiveRequest: a listener is waiting for audio.
    ///   - isPlayingArticle: the audio belongs to the article that is playing.
    ///   - inBackgroundBurst: a background burst is running (less than the low-water mark of
    ///     listening was ready ahead when it started, and it hasn't reached the high-water mark).
    static func decide(phase: AppRunState.Phase, rendersInBackground: Bool,
                       isLiveRequest: Bool, isPlayingArticle: Bool, inBackgroundBurst: Bool) -> RenderAdmission {
        guard modelCallsAllowed(phase: phase, rendersInBackground: rendersInBackground) else {
            return isLiveRequest ? .deferToApple : .park
        }
        switch phase {
        case .active:
            return .render
        case .inactive:
            return rendersInBackground || isLiveRequest ? .render : .park
        case .background:
            return isLiveRequest || (isPlayingArticle && inBackgroundBurst) ? .render : .park
        }
    }

    /// The hard rule under every decision: no Core ML call starts in the background (no GPU there,
    /// and the CPU fallback is the libBNNS crash path). Hosts without Core ML may run.
    static func modelCallsAllowed(phase: AppRunState.Phase, rendersInBackground: Bool) -> Bool {
        phase != .background || rendersInBackground
    }
}
