import Foundation

/// What the render queue renders: the on-device engine that is loaded and the voice it speaks in,
/// as `ArticleAudioCache` keys (`engineID` "local.kokoro", `cacheVoice` "kokoro.af_heart"). Every
/// render, readiness check and publish of the queue reads it from the one owner
/// (`SynthQueueContext.renderTarget`), so a render made for one voice is never filed under another.
struct RenderTarget: Equatable {
    var engineID: String
    var cacheVoice: String
}

/// What `GlobalSynthQueue` needs from its owner. `LocalTTSCoordinator` in the app; a fake in tests.
@MainActor
protocol SynthQueueContext: AnyObject {
    var audioCache: ArticleAudioCache { get }
    /// What renders now; nil while no on-device engine is ready (Apple selected, a model loading,
    /// failed or deleted). The queue parks while it is nil: it never loads a model itself.
    var renderTarget: RenderTarget? { get }
    /// `ArticleAudioCache` engine key of the active local engine (loaded or loading): the plan
    /// the listen player cuts paragraphs by.
    var cacheEngineID: String { get }
    var chunkPlans: ChunkPlans { get }
    var synthRenderer: SynthChunkRendering { get }
    /// The Apple voice that speaks an article with `paragraphs` where the engine can't: the one
    /// the listen player falls back to for it (nil: the system voice).
    func appleFallbackVoice(for paragraphs: [String]) -> String?
    func noteBakeMarksChanged()
    /// An article is fully baked (drop its persisted pending job).
    func bakeCompleted(cacheKey: UUID)
    /// The active local host may render while the app is backgrounded (Kokoro ONNX CPU route).
    var activeRouteRendersInBackground: Bool { get }
    /// Article whose audio is playing right now (nil = none): its renders run at listener
    /// priority, and it is the only article baked ahead in the background.
    var playingCacheKey: UUID? { get }
    /// Listening time ready ahead of the playhead of the article playing: seconds of rendered
    /// audio the player can play without another render, at the listen speed. Counted up to
    /// `limit`; 0 when nothing plays. Background bursts start and stop on it
    /// (`BackgroundRenderWatermarks`).
    func readyAheadSeconds(upTo limit: TimeInterval) -> TimeInterval
}

extension SynthQueueContext {
    var activeRouteRendersInBackground: Bool { false }
    var playingCacheKey: UUID? { nil }
}

/// Renders one synth chunk with the active local engine, or with Apple as the fallback. Both
/// render at 1×: the listen speed is a time-stretch on the player.
@MainActor
protocol SynthChunkRendering: AnyObject {
    var engineShortName: String { get }
    func renderChunkToFile(text: String, destination: URL, context: [String: Any],
                           priority: RenderPriority) async throws -> TimeInterval
    func renderAppleFallback(text: String, destination: URL, voiceID: String?) async throws -> TimeInterval
}
