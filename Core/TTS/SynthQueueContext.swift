import Foundation

/// What the render queue renders an article's audio in: its own selection's engine and voice, as
/// `ArticleAudioCache` keys (`engineID` "local.kokoro", `cacheVoice` "kokoro.af_heart"). Every
/// render, readiness check and publish of the queue reads it from the one owner
/// (`SynthQueueContext.renderTarget(for:)`), so a render made for one voice is never filed under another.
struct RenderTarget: Equatable {
    var engineID: String
    var cacheVoice: String
    /// The engine's own voice id ("af_heart") the host speaks in for this audio; nil: the host's own.
    var engineVoice: String? = nil
}

/// What `GlobalSynthQueue` needs from its owner. `LocalTTSCoordinator` in the app; a fake in tests.
@MainActor
protocol SynthQueueContext: AnyObject {
    var audioCache: ArticleAudioCache { get }
    /// C138a: what renders for `cacheKey`: its own selection (engine + voice), loaded or not. nil:
    /// no registered engine speaks it. No other voice is substituted.
    func renderTarget(for cacheKey: UUID) -> RenderTarget?
    /// `renderTarget(for:)`, and an article with no voice yet takes that voice now (its first audio
    /// is about to render).
    func lockedRenderTarget(for cacheKey: UUID) -> RenderTarget?
    /// The engine whose host is loaded (nil: none). Only the queue's worker changes it.
    var residentEngineID: String? { get }
    /// Load `engineID`'s host, the resident one let go first, at `priority` (a listener's waited
    /// chunk: `.listener`; a preload or bake-ahead: `.bakeAhead`); waits for a load of it already
    /// in flight rather than starting another. Throws when it can't load. The worker's alone.
    func makeResident(_ engineID: String, priority: RenderPriority) async throws
    /// Let `engineID`'s host go if it is the one loaded or loading (the worker calls it between
    /// model calls); the next work for it loads a fresh one.
    func dropHost(_ engineID: String)
    var chunkPlans: ChunkPlans { get }
    var synthRenderer: SynthChunkRendering { get }
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
    func lockedRenderTarget(for cacheKey: UUID) -> RenderTarget? { renderTarget(for: cacheKey) }
    var activeRouteRendersInBackground: Bool { false }
    var playingCacheKey: UUID? { nil }
}

/// Renders one synth chunk with the resident engine, at 1×: the listen speed is a time-stretch on
/// the player.
@MainActor
protocol SynthChunkRendering: AnyObject {
    var engineShortName: String { get }
    /// Throws, rendering nothing, unless `engineID`'s host is the one loaded: it never loads one.
    func renderChunkToFile(text: String, destination: URL, engineID: String,
                           request: ChunkRenderRequest) async throws -> TimeInterval
}
