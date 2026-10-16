import Foundation

/// The audio side of library changes (`LibraryStore+AudioWork`, deleting a page's downloads): the
/// audio files, and what the speech stack keeps in step with them, the render queue, the saved
/// bake jobs and the crash-resume target launch read. `LocalTTSCoordinator` in the app.
@MainActor
protocol LibraryAudioEffects: AnyObject {
    /// The pages' audio, by page key.
    var audioCache: ArticleAudioCache { get }
    /// Chunk plans by engine: what aligning audio with rebuilt paragraphs cuts them by.
    var chunkPlans: ChunkPlans { get }
    /// Bake jobs waiting for the engine: a rebuilt page's job follows its paragraphs.
    var pendingBakes: PendingBakeJobStore { get }
    /// The crash-resume file: library work moves the point it names along with the page.
    var resumePoints: ListenResumePointStore { get }
    /// `key`'s audio, queued renders and saved bake job are deleted.
    func clearListenAudio(for key: UUID) throws
    /// `key`'s queued renders and saved bake job go; its audio stays.
    func removeBakeJob(cacheKey key: UUID)
    /// `key`'s audio is a saved page's: kept, and its queued renders no longer ephemeral.
    func markListenCacheSaved(_ key: UUID)
    /// `key`'s audio and queued renders go on the ephemeral TTL (kept until the cache's age
    /// prune), filed under `canonicalURL`.
    func markListenCacheEphemeral(_ key: UUID, canonicalURL: String?)
    /// Audio changed outside the render queue: what shows rendered audio redraws.
    func noteBakeMarksChanged()
    /// The library moved the page the crash-resume target names (read at launch, before the
    /// library's maintenance): the target follows, as `move` places it.
    func remapPendingResume(article: UUID, _ move: (ListenResumeTarget) -> ListenResumeTarget)
}
