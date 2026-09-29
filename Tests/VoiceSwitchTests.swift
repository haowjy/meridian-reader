import XCTest
@testable import Reader

/// One voice per article: after a voice (or engine) switch, old-voice CAFs stay playable until
/// each paragraph is re-rendered, re-rendering replaces that paragraph's file, bake marks count
/// only the new voice, and nothing of the old voice is left once the article is complete.
@MainActor
final class VoiceSwitchTests: XCTestCase {
    private var roots: [URL] = []
    private var contexts: [FakeQueueContext] = []
    private let kokoro = "local.kokoro"
    private let heart = "kokoro.af_heart"
    private let bella = "kokoro.af_bella"

    override func tearDown() async throws {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        contexts.forEach { $0.cleanUp() }
        roots = []
        contexts = []
    }

    private func tempCache() -> ArticleAudioCache {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceSwitch-\(UUID().uuidString)")
        roots.append(root)
        return ArticleAudioCache(root: root)
    }

    /// Store paragraph `i` as a tone CAF of `seconds` (duration identifies which voice wrote it).
    private func store(_ cache: ArticleAudioCache, _ key: UUID, _ i: Int, engine: String? = nil,
                       voice: String, seconds: Double) throws {
        let src = cache.root.appendingPathComponent("src-\(UUID().uuidString).caf")
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: seconds, sampleRate: 24_000), sampleRate: 24_000, to: src)
        try cache.storeParagraph(articleID: key, paragraphIndex: i, sourceURL: src, duration: seconds,
                                 engineID: engine ?? kokoro, voiceID: voice, rate: 1, text: "p\(i)")
        try FileManager.default.removeItem(at: src)
    }

    private func ready(_ cache: ArticleAudioCache, _ key: UUID, _ n: Int, engine: String? = nil, voice: String) -> [Int] {
        cache.readyIndices(articleID: key, paragraphCount: n, engineID: engine ?? kokoro, voiceID: voice).sorted()
    }

    private func cafFiles(_ cache: ArticleAudioCache, _ key: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: cache.directory(for: key).path)) ?? [])
            .filter { $0.hasSuffix(".caf") }.sorted()
    }

    private func duration(_ url: URL?) -> Double {
        guard let url, let f = try? AVAudioFileBox(url) else { return -1 }
        return f.seconds
    }

    func testVoiceSwitchKeepsOneVoicePerArticle() throws {
        let cache = tempCache()
        let key = UUID()
        for i in 0..<3 { try store(cache, key, i, voice: heart, seconds: 0.2) }
        XCTAssertEqual(ready(cache, key, 3, voice: heart), [0, 1, 2])

        // Switch to Bella: nothing counts as ready (marks/% = new voice), all still playable.
        XCTAssertEqual(ready(cache, key, 3, voice: bella), [])
        XCTAssertEqual(cache.missingIndices(articleID: key, paragraphCount: 3, engineID: kokoro, voiceID: bella), [0, 1, 2])
        for i in 0..<3 {
            XCTAssertNil(cache.audioURL(articleID: key, paragraphIndex: i, engineID: kokoro, voiceID: bella))
            XCTAssertNotNil(cache.playableAudioURL(articleID: key, paragraphIndex: i, engineID: kokoro, voiceID: bella),
                            "p\(i): old-voice audio still playable")
        }

        // p1 re-rendered in Bella: its Heart file is gone (replaced), p0/p2 still Heart.
        try store(cache, key, 1, voice: bella, seconds: 0.4)
        XCTAssertEqual(ready(cache, key, 3, voice: bella), [1])
        XCTAssertEqual(ready(cache, key, 3, voice: heart), [0, 2])
        let mid = try cache.loadIndex(for: key)
        XCTAssertEqual(mid.voiceID, bella)
        XCTAssertEqual(mid.paragraphs.filter { $0.voiceID == heart }.map(\.index), [0, 2])
        XCTAssertEqual(cafFiles(cache, key), ["p-0000.caf", "p-0001.caf", "p-0002.caf"], "one file per paragraph")
        XCTAssertEqual(duration(cache.playableAudioURL(articleID: key, paragraphIndex: 1, engineID: kokoro, voiceID: bella)),
                       0.4, accuracy: 0.01, "p1 plays the new voice")
        XCTAssertEqual(duration(cache.playableAudioURL(articleID: key, paragraphIndex: 0, engineID: kokoro, voiceID: bella)),
                       0.2, accuracy: 0.01, "p0 still plays the old voice")
        XCTAssertEqual(cache.status(for: key, expectedParagraphs: 3), .partial(ready: 1, total: 3))

        // Done: only Bella remains.
        try store(cache, key, 0, voice: bella, seconds: 0.4)
        try store(cache, key, 2, voice: bella, seconds: 0.4)
        XCTAssertEqual(ready(cache, key, 3, voice: bella), [0, 1, 2])
        XCTAssertEqual(ready(cache, key, 3, voice: heart), [])
        let done = try cache.loadIndex(for: key)
        XCTAssertTrue(done.paragraphs.allSatisfy { $0.voiceID == nil && $0.engineID == nil }, "no old-voice entries")
        XCTAssertEqual(cafFiles(cache, key).count, 3)
        XCTAssertEqual(cache.status(for: key, expectedParagraphs: 3), .ready(paragraphCount: 3))
    }

    func testFinalizeRemovesLeftoverOldVoiceUnits() throws {
        let cache = tempCache()
        let key = UUID()
        for i in 0..<4 { try store(cache, key, i, voice: heart, seconds: 0.2) }
        // Article now has 3 paragraphs; all re-rendered in Bella. p3 (Heart) is a leftover.
        for i in 0..<3 { try store(cache, key, i, voice: bella, seconds: 0.4) }
        XCTAssertEqual(cafFiles(cache, key).count, 4)
        XCTAssertEqual(cache.finalizeVoiceSwitch(articleID: key, paragraphCount: 4, engineID: kokoro, voiceID: bella), 0,
                       "not complete for 4 paragraphs → keep")
        let freed = cache.finalizeVoiceSwitch(articleID: key, paragraphCount: 3, engineID: kokoro, voiceID: bella)
        XCTAssertGreaterThan(freed, 0)
        XCTAssertEqual(cafFiles(cache, key), ["p-0000.caf", "p-0001.caf", "p-0002.caf"])
        XCTAssertEqual(try cache.loadIndex(for: key).paragraphs.map(\.index), [0, 1, 2])
    }

    func testEngineSwitchFollowsTheSameRule() throws {
        let cache = tempCache()
        let key = UUID()
        let fake = FakeEngineProvider.fakeID.rawValue
        for i in 0..<2 { try store(cache, key, i, voice: heart, seconds: 0.2) }
        XCTAssertEqual(ready(cache, key, 2, engine: fake, voice: "fake.default"), [])
        XCTAssertNotNil(cache.playableAudioURL(articleID: key, paragraphIndex: 1, engineID: fake, voiceID: "fake.default"))
        try store(cache, key, 0, engine: fake, voice: "fake.default", seconds: 0.4)
        let index = try cache.loadIndex(for: key)
        XCTAssertEqual(index.engineID, fake)
        XCTAssertEqual(index.paragraphs.first { $0.index == 1 }?.engineID, kokoro, "stale unit keeps its engine")
        XCTAssertEqual(ready(cache, key, 2, voice: heart), [1])
        XCTAssertEqual(ready(cache, key, 2, engine: fake, voice: "fake.default"), [0])
    }

    /// Queue level: a queued article already baked in the old voice is re-rendered in the new
    /// voice after `engineDidChange`, and no old-voice audio remains when it completes.
    func testQueueRerendersInNewVoiceAfterSwitch() async throws {
        let ctx = FakeQueueContext(provider: FakeEngineProvider())
        contexts.append(ctx)
        let queue = GlobalSynthQueue()
        queue.attach(coordinator: ctx)
        let key = UUID()
        let paras = ["First paragraph here.", "Second paragraph, a bit longer than the first.", "Third."]
        queue.openArticle(cacheKey: key, paragraphs: paras, rate: 1, voiceID: "fake.a", isEphemeral: false)
        try await waitIdle(queue)
        XCTAssertEqual(ready(ctx.audioCache, key, 3, engine: ctx.cacheEngineID, voice: "fake.a"), [0, 1, 2])

        // Background job still carries the old voice when the user switches.
        queue.isPausedForProbe = true
        queue.openArticle(cacheKey: key, paragraphs: paras, rate: 1, voiceID: "fake.a", isEphemeral: false)
        ctx.activeVoice = "fake.b"
        queue.engineDidChange()
        queue.isPausedForProbe = false
        try await waitIdle(queue)

        XCTAssertEqual(ready(ctx.audioCache, key, 3, engine: ctx.cacheEngineID, voice: "fake.b"), [0, 1, 2])
        XCTAssertEqual(ready(ctx.audioCache, key, 3, engine: ctx.cacheEngineID, voice: "fake.a"), [])
        let index = try ctx.audioCache.loadIndex(for: key)
        XCTAssertEqual(index.voiceID, "fake.b")
        XCTAssertTrue(index.paragraphs.allSatisfy { $0.voiceID == nil })
        XCTAssertEqual(cafFiles(ctx.audioCache, key).count, 3, "no staging or old-voice files left")
        XCTAssertEqual(ctx.completed, [key, key])
    }

    private func waitIdle(_ queue: GlobalSynthQueue, timeout: TimeInterval = 20) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 20_000_000)
        while queue.isWorkerRunning {
            if Date().timeIntervalSince(start) > timeout { XCTFail("worker never went idle"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

import AVFoundation

/// Tiny helper: CAF duration in seconds.
private struct AVAudioFileBox {
    let seconds: Double
    init(_ url: URL) throws {
        let f = try AVAudioFile(forReading: url)
        seconds = Double(f.length) / f.processingFormat.sampleRate
    }
}
