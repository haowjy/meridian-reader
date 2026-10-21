import SwiftData
import XCTest
@testable import MeridianReader

/// C134 retention and the C136 rename's on-disk compatibility: the two guards against losing
/// what the user chose to keep.
@MainActor
final class RetentionTests: XCTestCase {
    /// Prepared audio is never evicted, even far outside Recent; unsaved articles beyond the last
    /// 50 started are deleted; a saved article outside Recent keeps its text but loses its audio
    /// from listening.
    func testPreparedAudioIsNeverEvictedAndUnsavedBeyond50AreRemoved() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        let library = env.library!
        let tts = try XCTUnwrap(library.audio as? LocalTTSCoordinator)
        func giveAudio(_ key: UUID) throws {
            try FileManager.default.createDirectory(at: tts.audioCache.directory(for: key), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: tts.audioCache.indexURL(for: key))
        }
        let prepared = try library.save(env.article("https://e.com/prepared"))
        let saved = try library.save(env.article("https://e.com/saved"))
        let preparedKey = try XCTUnwrap(prepared.key), savedKey = try XCTUnwrap(saved.key)
        tts.preparedKey = { $0 == preparedKey }
        library.recordPlaybackStarted(prepared)
        library.recordPlaybackStarted(saved)
        try giveAudio(preparedKey)
        try giveAudio(savedKey)
        var unsaved: [Article] = []
        for i in 0..<(LibraryStore.recentLimit + 5) {
            env.now = env.now.addingTimeInterval(60)
            unsaved.append(library.recordPlayback(env.article("https://e.com/\(i)", title: "A\(i)")))
        }
        let left = try env.context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.addedAt == nil }))
        XCTAssertEqual(left.count, LibraryStore.recentLimit, "only the last 50 unsaved articles stay")
        XCTAssertTrue(tts.audioCache.hasCache(for: preparedKey), "prepared audio is never evicted")
        XCTAssertFalse(tts.audioCache.hasCache(for: savedKey), "audio from listening goes once out of Recent")
        XCTAssertNotNil(library.article(key: savedKey), "the saved article itself stays")
    }

    /// A list written before the rename (and before C121) still reads as prepared: the file name
    /// and its keys are kept on disk (`Downloads.json`, "page").
    func testOldDownloadsJSONStillReadsAsPrepared() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Downloads-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID(), key = UUID()
        let json = """
        [{"id":"\(id)","target":{"page":{"_0":"\(key)"}},"title":"T","addedAt":0,"isPaused":false,
          "entries":[{"key":"\(key)","state":"done"}],"keptVoice":"kokoro.af_heart"}]
        """
        try Data(json.utf8).write(to: url)
        let records = PrepareListStore(url: url).load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.target, .article(key))
        XCTAssertTrue(records[0].hasPrepared(key, current: "kokoro.af_heart") { _ in "kokoro.af_heart" })
        XCTAssertEqual(AppDirectories.preparedAudio.lastPathComponent, "Downloads.json")
        XCTAssertEqual(PrepareCenter.rateKey, "downloads.wordsPerSecond")
    }
}
