import Foundation

/// Where the local listen player gets audio for one play: one article's paragraphs in one engine
/// voice. Rendered paragraphs come from the audio cache; the rest is rendered chunk by chunk by
/// the render queue. Bound when playback starts and dropped on stop / the next play.
@MainActor
protocol ListenUnitSource: AnyObject {
    /// Cache key of the article (the library page's key, or the reader key of an unsaved page).
    var articleID: UUID { get }
    var paragraphs: [String] { get }
    /// Short name of the engine rendering this audio (logs, listen-bar notes).
    var engineName: String { get }
    /// The engine keeps rendering while the app is in the background (Kokoro ONNX CPU route).
    var rendersInBackground: Bool { get }

    /// Load the engine's model if needed. Throws when it can't load.
    func prepare() async throws
    /// The whole paragraph's audio when it is rendered (in this voice, or in the previous voice
    /// until it is re-rendered).
    func renderedParagraph(_ paragraph: Int) -> RenderedParagraph?
    /// Synth chunks of the paragraph's text, in render order.
    func chunks(paragraph: Int) -> [String]
    /// Durations of the chunks stitched into the paragraph's file (nil: a single render, or unknown).
    func chunkDurations(paragraph: Int) -> [TimeInterval]?
    /// Wait for a playable file holding chunk `chunk` of `paragraph`.
    func chunk(paragraph: Int, chunk: Int) async throws -> GlobalSynthQueue.ChunkResolution
    /// Is the chunk playable now, without waiting for a render?
    func isChunkReady(paragraph: Int, chunk: Int) -> Bool
    /// What the render worker is doing relative to `paragraph`.
    func workerStatus(paragraph: Int) -> RenderWorkerStatus
    /// Render `text` with Apple TTS into `destination` (the engine can't provide it in time).
    func renderApple(_ text: String, to destination: URL) async throws
    /// Production restarts at `paragraph`: render from there first.
    func focus(paragraph: Int)
}

struct RenderedParagraph: Equatable {
    var url: URL
    /// Durations of the chunks stitched into `url` (nil: a single render, or unknown).
    var chunkDurations: [TimeInterval]?
}

enum RenderWorkerStatus: Equatable {
    case idle
    /// Rendering (a chunk of) the asked-about paragraph of this article.
    case renderingThisParagraph
    /// Mid-call on another paragraph or another article.
    case busyElsewhere
}

/// `ListenUnitSource` over the coordinator's render queue, audio cache and synth service.
@MainActor
final class QueueUnitSource: ListenUnitSource {
    private(set) var articleID: UUID
    let paragraphs: [String]
    /// Cache keys of the audio this play uses (the engine and voice when playback started; an
    /// engine or voice change restarts playback with a new source).
    private let cacheEngineID: String
    private let voiceKey: String
    /// Apple voice for fallback renders (the article's effective Apple voice).
    private let appleVoiceID: String?
    private let coordinator: LocalTTSCoordinator
    private var queue: GlobalSynthQueue { coordinator.synthQueue }
    private var cache: ArticleAudioCache { coordinator.audioCache }

    init(coordinator: LocalTTSCoordinator, articleID: UUID, paragraphs: [String], appleVoiceID: String?) {
        self.coordinator = coordinator
        self.articleID = articleID
        self.paragraphs = paragraphs
        self.appleVoiceID = appleVoiceID
        self.cacheEngineID = coordinator.cacheEngineID
        self.voiceKey = coordinator.cacheVoiceID(appleVoice: appleVoiceID)
    }

    /// Save landed on a different key than the reader's: keep playing under the new one.
    func rekey(to id: UUID) { articleID = id }

    var engineName: String { coordinator.synth.engineShortName }
    var rendersInBackground: Bool { coordinator.synth.rendersInBackground }

    func prepare() async throws { try await coordinator.synth.prepare() }

    func renderedParagraph(_ paragraph: Int) -> RenderedParagraph? {
        guard let url = cache.playableAudioURL(articleID: articleID, paragraphIndex: paragraph,
                                               engineID: cacheEngineID, voiceID: voiceKey),
              cache.isUsableAudioFile(url) else { return nil }
        return RenderedParagraph(url: url, chunkDurations: chunkDurations(paragraph: paragraph))
    }

    /// Rendered in this play's voice (not an older voice's file awaiting re-render).
    func isRenderedInThisVoice(paragraph: Int) -> Bool {
        cache.audioURL(articleID: articleID, paragraphIndex: paragraph, engineID: cacheEngineID, voiceID: voiceKey) != nil
    }

    func chunks(paragraph: Int) -> [String] {
        guard paragraphs.indices.contains(paragraph) else { return [] }
        return queue.chunkTexts(for: paragraphs[paragraph])
    }

    func chunkDurations(paragraph: Int) -> [TimeInterval]? {
        cache.entry(articleID: articleID, paragraphIndex: paragraph)?.chunkDurations
    }

    func chunk(paragraph: Int, chunk: Int) async throws -> GlobalSynthQueue.ChunkResolution {
        try await queue.ensureChunk(
            cacheKey: articleID, paragraphIndex: paragraph, chunk: chunk, text: paragraphs[paragraph],
            paragraphs: paragraphs, voiceID: voiceKey,
            isEphemeral: cache.loadMeta(for: articleID)?.kind == .ephemeral)
    }

    func isChunkReady(paragraph: Int, chunk: Int) -> Bool {
        queue.isChunkReady(cacheKey: articleID, paragraphIndex: paragraph, chunk: chunk,
                           text: paragraphs[paragraph], voiceID: voiceKey)
    }

    func workerStatus(paragraph: Int) -> RenderWorkerStatus {
        guard let active = queue.activeBakeCacheKey else { return .idle }
        return active == articleID && queue.activeBakeIndex == paragraph ? .renderingThisParagraph : .busyElsewhere
    }

    func renderApple(_ text: String, to destination: URL) async throws {
        _ = try await coordinator.synth.renderAppleFallback(text: text, destination: destination, voiceID: appleVoiceID)
    }

    func focus(paragraph: Int) {
        queue.focusPlayhead(cacheKey: articleID, paragraph: paragraph)
    }
}
