import Foundation

/// May an on-device model call start now? One rule for the render queue and the renderer.
///
/// | App phase | Route renders in background (ONNX CPU) | Core ML route |
/// |---|---|---|
/// | active | render | render |
/// | inactive | render | listener's chunks only; bake-ahead parks |
/// | background | listener's chunks; bake-ahead of the playing article during a burst (`BackgroundRenderWatermarks`); a download's job on its turn (C94: audio playing, the playing article safely ahead); other articles park | no model call: a listener's chunk goes to Apple, bake-ahead parks |
///
/// While no on-device engine is ready (no `RenderTarget`: Apple selected, a model loading, failed
/// or deleted) no model call starts in any phase: a listener's chunk goes to Apple and bake-ahead
/// parks until an engine is ready. Thermal / Low Power Mode holds on bake-ahead are separate
/// (`BakeConditions`).
enum RenderAdmission: Equatable {
    /// Start the call.
    case render
    /// Not now: wait until the app is active again (or a listener asks).
    case park
    /// Not now, and a listener is waiting: the player speaks this audio with Apple instead.
    case deferToApple

    /// - Parameters:
    ///   - engineReady: an on-device engine is loaded to render with.
    ///   - rendersInBackground: the active host keeps rendering while backgrounded (no Core ML).
    ///   - isLiveRequest: a listener is waiting for audio.
    ///   - isPlayingArticle: the audio belongs to the article that is playing.
    ///   - inBackgroundBurst: a background burst is running (less than the low-water mark of
    ///     listening was ready ahead when it started, and it hasn't reached the high-water mark).
    ///   - isDownloadTurn: the audio is a download's, audio is playing, and the playing article
    ///     needs nothing rendered now (no burst, or nothing of it left to render) (C94).
    static func decide(engineReady: Bool, phase: AppRunState.Phase, rendersInBackground: Bool,
                       isLiveRequest: Bool, isPlayingArticle: Bool, inBackgroundBurst: Bool,
                       isDownloadTurn: Bool = false) -> RenderAdmission {
        guard engineReady, modelCallsAllowed(phase: phase, rendersInBackground: rendersInBackground) else {
            return isLiveRequest ? .deferToApple : .park
        }
        switch phase {
        case .active:
            return .render
        case .inactive:
            return rendersInBackground || isLiveRequest ? .render : .park
        case .background:
            return isLiveRequest || (isPlayingArticle && inBackgroundBurst) || isDownloadTurn ? .render : .park
        }
    }

    /// The hard rule under every decision: no Core ML call starts in the background (no GPU there,
    /// and the CPU fallback is the libBNNS crash path). Hosts without Core ML may run.
    static func modelCallsAllowed(phase: AppRunState.Phase, rendersInBackground: Bool) -> Bool {
        phase != .background || rendersInBackground
    }
}
