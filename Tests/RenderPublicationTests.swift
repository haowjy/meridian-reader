import SwiftData
import XCTest
@testable import Reader

/// The render queue stitches a paragraph off the main actor and publishes it on the main actor
/// only if the queue still wants that text on that paragraph. An alignment of the article's audio
/// that lands while the stitch is in flight never leaves the index naming a missing file, or a
/// paragraph holding another text's audio.
@MainActor
final class RenderPublicationTests: XCTestCase {
    private var contexts: [FakeQueueContext] = []
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        contexts.forEach { $0.cleanUp() }
        contexts = []
        cleanups.forEach { $0() }
        cleanups = []
    }

    /// The speech stack over the fake on-device engine (loaded), with its own audio cache.
    private func makeSpeech() async -> SpeechController {
        let suite = "RenderPublication-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(FakeEngineProvider.fakeID.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), FakeEngineProvider()], gate: { _ in true })
        let root = FileManager.default.temporaryDirectory.appending(path: "RenderPublication-\(UUID().uuidString)")
        let tts = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                      audioCache: ArticleAudioCache(root: root.appending(path: "cache")),
                                      crashGuard: EngineCrashGuard(directory: root.appending(path: "guard")))
        await tts.selectEngine(FakeEngineProvider.fakeID)
        let speech = SpeechController(engines: registry, localTTS: tts,
                                      audioSession: ListenAudioSession(managesSystemSession: false),
                                      nowPlaying: NowPlayingController(commandCenter: nil, infoCenter: nil),
                                      appleEngine: FakeListenEngine(), resumePoints: nil)
        cleanups.append {
            speech.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return speech
    }

    /// The page at `url` as extracted, with `paragraphs` as its text.
    private func article(_ url: String, _ paragraphs: [String]) -> ReaderArticle {
        let u = URL(string: url)!
        let extracted = ExtractedArticle(title: "Refreshed", siteName: nil, cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
        return ReaderArticle(id: ArticleIdentity.articleKey(url: u), url: u, extracted: extracted)
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

    /// A page opens in the Reader with [A, B], which makes its job #1 (rendering is held
    /// meanwhile, as on a hot device, so everything renders after the Save), and the Reader
    /// closes without listening. The browser refreshes the page, whose text is now [C, A, B], and
    /// ⋯ → Save saves it. Save aligns the page's audio with the new paragraphs, and the job, still
    /// #1 with its plan, takes them too: A's render never lands on paragraph 0, and every paragraph
    /// ends with audio of its own text.
    func testBrowserSaveOfNewerTextGivesTheReadersJobTheNewParagraphs() async throws {
        let speech = await makeSpeech()
        let tts = speech.localTTS
        XCTAssertTrue(tts.usesLocalEngine)
        let container = try LibraryStoreConfiguration.makeInMemoryContainer()
        let library = LibraryStore(context: container.mainContext, tts: tts)
        let a = "Alpha is the paragraph the page opened with.", b = "Bravo comes after it.", c = "Charlie is new at the top."
        let opened = article("https://example.com/refreshed", [a, b])
        let refreshed = article("https://example.com/refreshed", [c, a, b])
        XCTAssertEqual(opened.document.paragraphs, [a, b])
        XCTAssertEqual(refreshed.document.paragraphs, [c, a, b])
        let key = opened.id
        XCTAssertEqual(refreshed.id, key)
        let voice = tts.normalizedCacheVoice(speech.cacheVoiceID)

        // Opened in the Reader (as `ReaderSheetScreen.prepareListen` does), then closed.
        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false) }
        tts.prepareListenIdentity(key: key, paragraphs: opened.document.paragraphs, isLivePlayback: false)
        tts.warmListenAudio(cacheKey: key, paragraphs: opened.document.paragraphs, voiceID: speech.cacheVoiceID, isEphemeral: true)
        XCTAssertEqual(tts.synthQueue.primaryCacheKey, key)

        // The browser refreshed the page: ⋯ → Save (as `PageArticleService.save` does).
        XCTAssertEqual(ArticleSaveCoordinator(library: library, speech: speech).save(refreshed), key)
        XCTAssertEqual(tts.synthQueue.primaryCacheKey, key, "still #1")
        XCTAssertEqual(tts.synthQueue.isEphemeral(cacheKey: key), false)
        let plan = try XCTUnwrap(tts.synthQueue.planDescription(for: key))
        XCTAssertTrue(plan.contains("paragraphCount: 3"), "the plan covers the new paragraphs: \(plan)")

        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .nominal, isLowPowerModeEnabled: false) }
        tts.synthQueue.bakeConditionsChanged()
        try await waitIdle(tts.synthQueue)

        let cache = tts.audioCache
        XCTAssertEqual(cache.entry(articleID: key, paragraphIndex: 0)?.textHash, ArticleIdentity.paragraphHash(c),
                       "paragraph 0 holds C's audio, not A's")
        assertSound(cache.index(for: key), cache, key, [c, a, b], "in memory")
        assertSound(cache.readIndexFile(for: key), cache, key, [c, a, b], "saved")
        XCTAssertEqual(cache.readyIndices(articleID: key, paragraphCount: 3, engineID: tts.cacheEngineID, voiceID: voice),
                       [0, 1, 2], "every paragraph rendered")
    }
}
