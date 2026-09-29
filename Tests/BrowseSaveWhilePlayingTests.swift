import XCTest
@testable import Reader

/// Crash flow 2026-09-24 22:00 (Kokoro libBNNS SIGSEGV, FluidAudio #844): Browse → Save → open
/// in Reader while a saved article was playing. The SIGSEGV itself is inside Apple's BNNS and
/// cannot run on the Simulator; what this reproduces is *our* bug in that flow, which multiplied
/// Core ML calls (crash exposure grows per call): opening the reader for the just-saved article
/// (not the live session) wiped the chunk scratch of the paragraph the queue was baking for it,
/// so already-rendered chunks were synthesized again (timing log: p2 c0 rendered at 22:00:06 and
/// again at 22:00:08.691, crash on the next call).
@MainActor
final class BrowseSaveWhilePlayingTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        cleanups.forEach { $0() }
        cleanups = []
    }

    private func makeCoordinator(_ provider: FakeEngineProvider) -> LocalTTSCoordinator {
        let suite = "BrowseSaveWhilePlaying-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(FakeEngineProvider.fakeID.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), provider], gate: { _ in true })
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("BrowseSave-\(UUID().uuidString)")
        let guardDir = tmp.appendingPathComponent("BrowseSaveGuard-\(UUID().uuidString)")
        cleanups.append {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: guardDir)
        }
        return LocalTTSCoordinator(engines: registry, defaults: defaults,
                                   audioCache: ArticleAudioCache(root: root),
                                   crashGuard: EngineCrashGuard(directory: guardDir))
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 30) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 30_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > timeout { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func sentence(_ n: Int) -> String {
        "Sentence number \(n) is here, and it runs on for a little while longer."
    }

    func testOpeningReaderForJustSavedArticleWhileAnotherPlaysDoesNotReRenderChunks() async throws {
        let provider = FakeEngineProvider(config: .init(latency: 0.15))
        let c = makeCoordinator(provider)
        await c.selectEngine(FakeEngineProvider.fakeID)
        XCTAssertTrue(c.localHostReady)
        let voice = c.normalizedCacheVoice("fake.default")

        // Saved article A is playing from its baked audio.
        let a = UUID()
        let aParas = ["The saved article that is already playing has its own words."]
        c.synthQueue.openArticle(cacheKey: a, paragraphs: aParas, rate: 1, voiceID: voice, isEphemeral: false)
        try await waitIdle(c.synthQueue)
        XCTAssertNotNil(c.audioCache.audioURL(articleID: a, paragraphIndex: 0, engineID: c.cacheEngineID, voiceID: voice))

        // Browse → Save article B: its bake starts (multi-chunk first paragraph).
        let b = UUID()
        let bParas = [(1...5).map(sentence).joined(separator: " "), sentence(9)]
        let chunks0 = c.synthQueue.chunkTexts(for: bParas[0])
        XCTAssertGreaterThanOrEqual(chunks0.count, 3)
        c.synthQueue.openArticle(cacheKey: b, paragraphs: bParas, rate: 1, voiceID: voice, isEphemeral: false)

        // Wait until chunk 0 of B p0 is on disk (mid-paragraph bake).
        let hash = ArticleIdentity.paragraphHash(bParas[0])
        let c0 = c.audioCache.chunkURL(articleID: b, paragraphIndex: 0, textHash: hash, chunk: 0)
        let start = Date()
        while !c.audioCache.isUsableChunk(c0) {
            if Date().timeIntervalSince(start) > 10 { XCTFail("chunk 0 never rendered"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // → Open in Reader. A is the live session, so B's open is NOT live playback.
        c.prepareListenIdentity(key: b, paragraphs: bParas, isLivePlayback: false)
        c.warmListenAudio(cacheKey: b, paragraphs: bParas, rate: 1, voiceID: voice, isEphemeral: false)
        try await waitIdle(c.synthQueue)

        let texts = provider.lastHost!.calls.filter(\.ok).map(\.text)
        let expected = aParas.flatMap(c.synthQueue.chunkTexts(for:)) + bParas.flatMap(c.synthQueue.chunkTexts(for:))
        // Multiset compare (chunk texts legitimately repeat across sentences).
        var extra = texts
        for t in expected { if let i = extra.firstIndex(of: t) { extra.remove(at: i) } }
        XCTAssertTrue(extra.isEmpty, "chunks synthesized more than once: \(extra)")
        XCTAssertEqual(texts.count, expected.count, "one Core ML call per chunk")
        for i in bParas.indices {
            XCTAssertNotNil(c.audioCache.audioURL(articleID: b, paragraphIndex: i, engineID: c.cacheEngineID, voiceID: voice))
        }
    }
}
