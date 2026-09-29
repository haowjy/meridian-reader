import XCTest
@testable import Reader

/// Chatterbox Nano removal: selection migrates (Kokoro if installed, else Apple), Nano-keyed
/// cached audio + index entries and orphan CAFs are deleted, model files are deleted once.
@MainActor
final class EngineRetirementTests: XCTestCase {
    private var roots: [URL] = []
    private let nano = SpeechEngineID.retiredChatterboxNano.rawValue

    override func tearDown() async throws {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        roots = []
    }

    private func tempDir(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        roots.append(url)
        return url
    }

    private func writeCAF(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LocalPCMWriter.write(FakeSynthHost.tone(seconds: 0.2, sampleRate: 24_000), sampleRate: 24_000, to: url)
    }

    private func writeIndex(_ cache: ArticleAudioCache, _ key: UUID, json: String) throws {
        try FileManager.default.createDirectory(at: cache.directory(for: key), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: cache.indexURL(for: key))
    }

    private func entry(_ i: Int, engine: String? = nil) -> String {
        let e = engine.map { #","engineID":"\#($0)","voiceID":"x""# } ?? ""
        return #"{"index":\#(i),"file":"p-000\#(i).caf","duration":0.2\#(e)}"#
    }

    func testPurgeRemovesRetiredEngineAudioIndexEntriesAndOrphans() throws {
        let cache = ArticleAudioCache(root: tempDir("Retire"))
        let nanoOnly = UUID(), kokoroOnly = UUID(), mixed = UUID(), legacy = UUID()
        for key in [nanoOnly, kokoroOnly, mixed, legacy] {
            for i in 0..<2 { try writeCAF(cache.directory(for: key).appendingPathComponent("p-000\(i).caf")) }
        }
        try writeIndex(cache, nanoOnly, json: #"{"engineID":"\#(nano)","voiceID":"system","createdAt":0,"paragraphs":[\#(entry(0)),\#(entry(1))]}"#)
        try writeIndex(cache, kokoroOnly, json: #"{"engineID":"local.kokoro","voiceID":"kokoro.af_heart","createdAt":0,"paragraphs":[\#(entry(0)),\#(entry(1))]}"#)
        try writeIndex(cache, mixed, json: #"{"engineID":"local.kokoro","voiceID":"kokoro.af_heart","createdAt":0,"paragraphs":[\#(entry(0)),\#(entry(1, engine: nano))]}"#)
        // Pre-engine-key index (Nano era): no engineID / voiceID.
        try writeIndex(cache, legacy, json: #"{"createdAt":0,"paragraphs":[\#(entry(0)),\#(entry(1))]}"#)
        try writeCAF(cache.directory(for: kokoroOnly).appendingPathComponent("p-0007.caf")) // orphan

        let report = cache.purgeEngine(nano)
        XCTAssertEqual(report.articles, 3)
        XCTAssertEqual(report.paragraphs, 5)
        XCTAssertGreaterThan(report.bytes, 0)
        XCTAssertEqual(report.orphanFiles, 1)

        XCTAssertFalse(cache.hasCache(for: nanoOnly), "index removed → no bake marks")
        XCTAssertFalse(cache.hasCache(for: legacy))
        XCTAssertEqual(cache.readyIndices(articleID: kokoroOnly, paragraphCount: 2, engineID: "local.kokoro",
                                          voiceID: "kokoro.af_heart"), [0, 1])
        XCTAssertEqual(try cache.loadIndex(for: mixed).paragraphs.map(\.index), [0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory(for: mixed).appendingPathComponent("p-0001.caf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.directory(for: kokoroOnly).appendingPathComponent("p-0007.caf").path))

        XCTAssertEqual(cache.purgeEngine(nano), .init(), "idempotent")
    }

    private func coordinator(selected: String, installed: Bool, provider: FakeEngineProvider,
                             defaults: UserDefaults, cacheRoot: URL) -> LocalTTSCoordinator {
        defaults.set(selected, forKey: LocalTTSCoordinator.engineIDKey)
        provider.installed = installed
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), provider], gate: { _ in true })
        return LocalTTSCoordinator(engines: registry, defaults: defaults,
                                   audioCache: ArticleAudioCache(root: cacheRoot),
                                   crashGuard: EngineCrashGuard(directory: tempDir("Guard")))
    }

    func testRetiredSelectionMovesToInstalledReplacementElseAppleAndCleanupRunsOnce() throws {
        var deleteCalls = 0
        let provider = FakeEngineProvider()
        provider.retired = [RetiredEngine(id: .retiredChatterboxNano, displayName: "Chatterbox Nano",
                                          doneKey: "test.retired.done", replacement: FakeEngineProvider.fakeID,
                                          deleteFiles: { deleteCalls += 1; return 1234 })]
        let suite = "EngineRetirementTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = tempDir("RetireCache")
        let key = UUID()
        let cache = ArticleAudioCache(root: root)
        try writeCAF(cache.directory(for: key).appendingPathComponent("p-0000.caf"))
        try writeIndex(cache, key, json: #"{"engineID":"\#(nano)","voiceID":"system","createdAt":0,"paragraphs":[\#(entry(0))]}"#)

        // Replacement not installed → Apple. Cleanup runs (cache + files).
        let c1 = coordinator(selected: nano, installed: false, provider: provider, defaults: defaults, cacheRoot: root)
        XCTAssertEqual(c1.selectedEngineID, .apple)
        XCTAssertEqual(defaults.string(forKey: LocalTTSCoordinator.engineIDKey), "apple")
        XCTAssertEqual(deleteCalls, 1)
        XCTAssertTrue(defaults.bool(forKey: "test.retired.done"))
        XCTAssertFalse(cache.hasCache(for: key), "Nano-keyed audio deleted")

        // Replacement installed → it. Cleanup does not run again.
        let c2 = coordinator(selected: nano, installed: true, provider: provider, defaults: defaults, cacheRoot: root)
        XCTAssertEqual(c2.selectedEngineID, FakeEngineProvider.fakeID)
        XCTAssertEqual(deleteCalls, 1, "one-time")
    }
}
