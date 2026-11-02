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
    /// The route whose host is loaded on `lane` (nil: none). Only the queue's worker changes it.
    func residentRoute(on lane: Lane) -> RenderRoute?
    /// Load a host built for `route` on its lane, that lane's resident one let go first (no other
    /// lane's), at `priority` (a listener's waited chunk: `.listener`; a preload or bake-ahead:
    /// `.bakeAhead`); waits for a load of it already in flight rather than starting another.
    /// Throws when it can't load. The worker's alone.
    func makeResident(_ route: RenderRoute, priority: RenderPriority) async throws
    /// Let `lane`'s host go if it is `engineID`'s (nil: whoever's), loaded, loading or failed (the
    /// worker calls it while nothing runs on that lane); the next work there loads a fresh one.
    func dropHost(on lane: Lane, of engineID: String?)
    var chunkPlans: ChunkPlans { get }
    var synthRenderer: SynthChunkRendering { get }
    /// `cacheKey`'s audio or its job changed (a paragraph published, old-voice audio removed, the
    /// job dropped): what follows its audio looks at that article again.
    func noteBakeMarksChanged(of cacheKey: UUID)
    /// An article is fully baked (drop its persisted pending job).
    func bakeCompleted(cacheKey: UUID)
    /// Article whose audio is playing right now (nil = none): its units ahead of the playhead
    /// have `playing` demand, and in the background calls start only while it is set.
    var playingCacheKey: UUID? { get }
    /// `engineID`'s routes (`SpeechEngineProvider.routes`): the only ones offered for its work.
    func routes(for engineID: String) -> [RenderRoute]
    /// Decides what renders next (`AppComposition.makeRenderPolicy`).
    var renderPolicy: RenderPolicy { get }
}

extension SynthQueueContext {
    func lockedRenderTarget(for cacheKey: UUID) -> RenderTarget? { renderTarget(for: cacheKey) }
}

/// Renders one synth chunk on a lane's resident host, at 1×: the listen speed is a time-stretch
/// on the player.
@MainActor
protocol SynthChunkRendering: AnyObject {
    /// Throws, rendering nothing, unless `route`'s host is the one loaded on its lane: it never
    /// loads one.
    func renderChunkToFile(text: String, destination: URL, route: RenderRoute,
                           request: ChunkRenderRequest) async throws -> TimeInterval
}
