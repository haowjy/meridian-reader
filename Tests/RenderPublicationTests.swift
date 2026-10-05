import XCTest
@testable import Reader

/// The render queue stitches a paragraph off the main actor and publishes it on the main actor
/// only if the queue still wants that text on that paragraph. An alignment of the article's audio
/// that lands while the stitch is in flight never leaves the index naming a missing file, or a
/// paragraph holding another text's audio.
@MainActor
final class RenderPublicationTests: XCTestCase {
    private var contexts: [FakeQueueContext] = []

    override func tearDown() async throws {
        contexts.forEach { $0.cleanUp() }
        contexts = []
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 20) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 20_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > timeout { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Every entry of `index` names a CAF that exists, rendered from its paragraph's text.
    private func assertSound(_ index: ArticleAudioCache.IndexFile?, _ cache: ArticleAudioCache, _ key: UUID,
                             _ paragraphs: [String], _ note: String, line: UInt = #line) {
        for e in index?.paragraphs ?? [] {
            XCTAssertTrue(cache.isUsableAudioFile(cache.directory(for: key).appending(path: e.file)),
                          "\(note): paragraph \(e.index) names \(e.file), which is gone", line: line)
            XCTAssertEqual(e.textHash, paragraphs.indices.contains(e.index) ? ArticleIdentity.paragraphHash(paragraphs[e.index]) : "-",
                           "\(note): paragraph \(e.index) holds another text's audio", line: line)
        }
    }

    /// An article is rendered in one voice; the voice changes and its first paragraph re-renders.
    /// While that render is stitched, the article is opened with a new paragraph at the top: its
    /// audio is aligned with the new paragraphs (the old first paragraph's CAF moves to
    /// paragraph 1, and `p-0000.caf` is deleted) and its job gets them, as the reader does. Then
    /// the render tries to publish: it is the old first paragraph's text, no longer what
    /// paragraph 0 holds, so it is dropped, and paragraph 0 renders with its own text.
    func testAnAlignmentDuringAStitchLeavesNoMissingFileAndNoStaleAudio() async throws {
        let ctx = FakeQueueContext(provider: FakeEngineProvider())
        contexts.append(ctx)
        let queue = GlobalSynthQueue()
        queue.attach(coordinator: ctx)
        let key = UUID()
        let old = ["First paragraph here.", "Second paragraph here.", "Third paragraph here."]
        queue.openArticle(cacheKey: key, paragraphs: old, voiceID: "fake.a", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(ctx.audioCache.readyIndices(articleID: key, paragraphCount: 3, engineID: ctx.cacheEngineID,
                                                   voiceID: "fake.a"), [0, 1, 2])

        let new = ["A new opening paragraph."] + old
        var aligned = false
        queue.beforePublishing = { k, p in
            guard !aligned, k == key, p == 0 else { return }
            aligned = true
            do { try ctx.audioCache.reconcile(articleID: key, paragraphs: new) } catch { XCTFail("align: \(error)") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: ctx.audioCache.paragraphFileURL(articleID: key, paragraphIndex: 0).path),
                           "the alignment deleted the old first paragraph's file")
            queue.openArticle(cacheKey: key, paragraphs: new, voiceID: "fake.b", isEphemeral: false)
        }
        ctx.activeVoice = "fake.b"
        queue.engineDidChange()
        queue.openArticle(cacheKey: key, paragraphs: old, voiceID: "fake.b", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertTrue(aligned, "the alignment landed while paragraph 0 was stitched")

        let cache = ctx.audioCache
        assertSound(cache.index(for: key), cache, key, new, "in memory")
        assertSound(cache.readIndexFile(for: key), cache, key, new, "saved")
        XCTAssertEqual(cache.readyIndices(articleID: key, paragraphCount: new.count, engineID: ctx.cacheEngineID,
                                          voiceID: "fake.b"), [0, 1, 2, 3], "every paragraph rendered in the new voice")
        let leftovers = (FileManager.default.subpaths(atPath: cache.directory(for: key).path) ?? [])
            .filter { ($0 as NSString).lastPathComponent.hasPrefix("paragraph-") }
        XCTAssertEqual(leftovers, [], "the dropped render's file is gone")
    }
}
