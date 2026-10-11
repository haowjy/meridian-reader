import Foundation

/// What `GlobalSynthQueue` needs from its owner. `LocalTTSCoordinator` in the app; a fake in tests.
@MainActor
protocol SynthQueueContext: AnyObject {
    var audioCache: ArticleAudioCache { get }
    /// `ArticleAudioCache` engine key of the active local engine.
    var cacheEngineID: String { get }
    /// Chunk sizing of the active local engine (from its `EngineDescriptor`).
    var activeChunkLimits: TextChunker.Limits { get }
    var synthRenderer: SynthChunkRendering { get }
    /// Apple voice for the never-skip fallback given a cache voice key (nil = system default).
    func fallbackAppleVoice(forCacheVoice voiceID: String) -> String?
    /// Map a (possibly stale) cache voice key onto the active engine/voice key space.
    func normalizedCacheVoice(_ voiceID: String) -> String
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
