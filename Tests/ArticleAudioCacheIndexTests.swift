import XCTest
@testable import Reader

/// `ArticleAudioCache` reads each article's `index.json` once and answers from memory: writes go
/// through to disk, missing / empty CAFs are dropped when the index is loaded.
@MainActor
final class ArticleAudioCacheIndexTests: XCTestCase {
    private var roots: [URL] = []
    private let engine = "local.kokoro"
    private let voice = "kokoro.af_heart"

    override func tearDown() async throws {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        roots = []
    }

    private func tempRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioIndex-\(UUID().uuidString)")
        roots.append(root)
        return root
    }

    private func store(_ cache: ArticleAudioCache, _ key: UUID, _ i: Int, chunkDurations: [Double]? = nil) throws {
        let src = cache.root.appendingPathComponent("src-\(UUID().uuidString).caf")
        try FileManager.default.createDirectory(at: cache.root, withIntermediateDirectories: true)
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: 0.2, sampleRate: 24_000), sampleRate: 24_000, to: src)
        try cache.storeParagraph(articleID: key, paragraphIndex: i, sourceURL: src, duration: 0.2,
                                 engineID: engine, voiceID: voice, text: "p\(i)", chunkDurations: chunkDurations)
        try FileManager.default.removeItem(at: src)
    }

    private func ready(_ cache: ArticleAudioCache, _ key: UUID) -> [Int] {
        cache.readyIndices(articleID: key, paragraphCount: 3, engineID: engine, voiceID: voice).sorted()
    }

    func testWritesGoThroughAndReadsComeFromMemory() throws {
        let root = tempRoot()
        let cache = ArticleAudioCache(root: root)
        let key = UUID()
        try store(cache, key, 0)
        try store(cache, key, 1, chunkDurations: [0.1, 0.1])
        XCTAssertEqual(ready(cache, key), [0, 1])
        XCTAssertEqual(cache.entry(articleID: key, paragraphIndex: 1)?.chunkDurations, [0.1, 0.1])

        // Another instance on the same root reads what was written.
        XCTAssertEqual(ArticleAudioCache(root: root).index(for: key), cache.index(for: key))

        // A file removed behind the cache's back: this instance doesn't look at the disk again…
        try FileManager.default.removeItem(at: cache.directory(for: key).appendingPathComponent("p-0001.caf"))
        XCTAssertEqual(ready(cache, key), [0, 1])
        // …and a fresh load drops the entry whose CAF is gone.
        let reloaded = ArticleAudioCache(root: root)
        XCTAssertEqual(ready(reloaded, key), [0])
        XCTAssertNil(reloaded.audioURL(articleID: key, paragraphIndex: 1, engineID: engine, voiceID: voice))
    }

    func testDeleteAndReconcileKeepMemoryInStep() throws {
        let cache = ArticleAudioCache(root: tempRoot())
        let key = UUID()
        for i in 0..<3 { try store(cache, key, i) }
        XCTAssertEqual(ready(cache, key), [0, 1, 2])

        // p0 removed from the article: p1 / p2 shift up one.
        cache.reconcile(articleID: key, paragraphs: ["p1", "p2"])
        XCTAssertEqual(ready(cache, key), [0, 1])
        XCTAssertEqual(cache.entry(articleID: key, paragraphIndex: 0)?.textHash, ArticleIdentity.paragraphHash("p1"))
        XCTAssertEqual(ArticleAudioCache(root: cache.root).index(for: key), cache.index(for: key))

        try cache.deleteAudio(for: key)
        XCTAssertNil(cache.index(for: key))
        XCTAssertEqual(ready(cache, key), [])
    }
}
