import Foundation

/// May an on-device model call start now? One rule for the render queue and the renderer.
///
/// | App phase | Host renders in background (the CPU routes) | Host that can't |
/// |---|---|---|
/// | active | render | render |
/// | inactive | render | listener's chunks only; bake-ahead parks |
/// | background | listener's chunks; bake-ahead of the playing article during a burst (`BackgroundRenderWatermarks`); a download's job on its turn (C94: audio playing, the playing article safely ahead); other articles park | no model call: a listener's chunk is deferred (playback pauses there), bake-ahead parks |
///
/// Admission doesn't depend on what is loaded: the worker loads the engine of the work it takes.
/// Thermal / Low Power Mode holds on bake-ahead are separate (`BakeConditions`).
enum RenderAdmission: Equatable {
    /// Start the call.
    case render
    /// Not now: wait until the app is active again (or a listener asks).
    case park
    /// Not now, and a listener is waiting: it is told at once (`LocalSynthError.deferredInBackground`)
    /// and playback pauses where its audio runs out.
    case deferred

    /// - Parameters:
    ///   - rendersInBackground: the active host keeps rendering while backgrounded (CPU only).
    ///   - isLiveRequest: a listener is waiting for audio.
    ///   - isPlayingArticle: the audio belongs to the article that is playing.
    ///   - inBackgroundBurst: a background burst is running (less than the low-water mark of
    ///     listening was ready ahead when it started, and it hasn't reached the high-water mark).
    ///   - isPrepareTurn: the audio is a prepare's, audio is playing, and the playing article
    ///     needs nothing rendered now (no burst, or nothing of it left to render) (C94).
    static func decide(phase: AppRunState.Phase, rendersInBackground: Bool,
                       isLiveRequest: Bool, isPlayingArticle: Bool, inBackgroundBurst: Bool,
                       isPrepareTurn: Bool = false) -> RenderAdmission {
        guard modelCallsAllowed(phase: phase, rendersInBackground: rendersInBackground) else {
            return isLiveRequest ? .deferred : .park
        }
        switch phase {
        case .active:
            return .render
        case .inactive:
            return rendersInBackground || isLiveRequest ? .render : .park
        case .background:
            return isLiveRequest || (isPlayingArticle && inBackgroundBurst) || isPrepareTurn ? .render : .park
        }
    }

    /// The hard rule under every decision: a host that can't render in the background (no GPU
    /// there) starts no call there. CPU-only hosts may run.
    static func modelCallsAllowed(phase: AppRunState.Phase, rendersInBackground: Bool) -> Bool {
        phase != .background || rendersInBackground
    }
}
