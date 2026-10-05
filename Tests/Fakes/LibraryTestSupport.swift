import Foundation
import SwiftData
import XCTest
@testable import Reader

/// A library over an in-memory container, with its own audio cache, defaults, bookmarks file and
/// ledger in a temp directory. `cleanUp()` removes them.
@MainActor
final class LibraryTestEnvironment {
    let dir: URL
    let container: ModelContainer
    let tts: LocalTTSCoordinator
    let defaults: UserDefaults
    let suite: String
    let legacy: LegacyLibrarySources
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var library: LibraryStore!
    /// Keys `stopPlaybackIfPlaying` was asked about while they were "playing".
    var playingKey: UUID?
    private(set) var stoppedKeys: [UUID] = []

    init(container: ModelContainer? = nil) throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LibraryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.container = try container ?? LibraryStoreConfiguration.makeInMemoryContainer()
        suite = "LibraryTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), KokoroStubProvider()], gate: { _ in true })
        tts = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                  audioCache: ArticleAudioCache(root: dir.appending(path: "TTSCache")),
                                  crashGuard: EngineCrashGuard(directory: dir.appending(path: "guard")))
        legacy = LegacyLibrarySources(bookmarksURL: dir.appending(path: "Bookmarks/bookmarks.json"),
                                      ledgerURL: dir.appending(path: "library-migration.json"), defaults: defaults)
        library = makeLibrary()
    }

    /// A second store over the same container (a relaunch, as far as the library is concerned).
    func makeLibrary() -> LibraryStore {
        let store = LibraryStore(context: container.mainContext, tts: tts, legacy: legacy, now: { [unowned self] in now })
        store.stopPlaybackIfPlaying = { [unowned self] key in
            if key == playingKey { stoppedKeys.append(key); playingKey = nil }
        }
        return store
    }

    var context: ModelContext { container.mainContext }
    var cache: ArticleAudioCache { tts.audioCache }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
        ListenResumePointStore.shared.clear()
    }

    // MARK: Fixtures

    func pages() -> [Page] { (try? context.fetch(FetchDescriptor<Page>())) ?? [] }
    func folders() -> [Folder] { (try? context.fetch(FetchDescriptor<Folder>())) ?? [] }

    /// A reader article for `url` with `paragraphs` as its text.
    func article(_ url: String, title: String = "Title", paragraphs: [String] = ["First paragraph here.", "Second paragraph here."],
                 key: UUID? = nil) -> ReaderArticle {
        let u = URL(string: url)!
        let html = paragraphs.map { "<p>\($0)</p>" }.joined()
        let extracted = ExtractedArticle(title: title, siteName: nil, cleanedHTML: html,
                                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
        return ReaderArticle(id: key ?? ArticleIdentity.articleKey(url: u), url: u, extracted: extracted)
    }

    /// A legacy saved row, as the app wrote it before the library.
    @discardableResult
    func legacyRow(_ url: String, id: UUID = UUID(), title: String = "Legacy", savedAt: Date,
                   paragraphs: [String] = ["One.", "Two.", "Three."], position: Int = 0, favicon: Data? = nil) -> SavedArticle {
        let row = SavedArticle(id: id, urlString: url, title: title, siteDomain: URL(string: url)?.host ?? "",
                               savedAt: savedAt, cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                               plainText: paragraphs.joined(separator: "\n\n"), wordCount: paragraphs.count,
                               estimatedMinutes: 1, excerpt: "", playbackParagraphIndex: position, faviconData: favicon)
        row.listenBlocksData = try? JSONEncoder().encode(paragraphs)
        row.listenBlocksVersion = ListenHTMLBlocks.version
        context.insert(row)
        try? context.save()
        return row
    }

    func writeBookmarks(_ bookmarks: [SiteBookmark]) throws {
        try FileManager.default.createDirectory(at: legacy.bookmarksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(bookmarks).write(to: legacy.bookmarksURL)
    }

    /// The pre-library listen history: last listened (seconds since 1970) and whether finished.
    func writeHistory(_ entries: [UUID: (at: Double, done: Bool)]) {
        let dict = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString, ListenHistory.Entry(at: $0.value.at, done: $0.value.done)) })
        defaults.set(try? JSONEncoder().encode(dict), forKey: ListenHistory.storageKey)
    }

    /// Stores a rendered paragraph for `key` (a short tone), as a finished bake would.
    func storeAudio(_ key: UUID, paragraph: Int, text: String, voice: String = "voiceA") throws {
        let tmp = dir.appending(path: "tone-\(UUID().uuidString).caf")
        try LocalPCMWriter.write([Float](repeating: 0.1, count: 2400), sampleRate: 24_000, to: tmp)
        try cache.storeParagraph(articleID: key, paragraphIndex: paragraph, sourceURL: tmp, duration: 0.1,
                                 engineID: tts.cacheEngineID, voiceID: voice, text: text)
    }

    /// Audio for every paragraph of `paragraphs`.
    func storeAudio(_ key: UUID, paragraphs: [String], voice: String = "voiceA") throws {
        for (i, text) in paragraphs.enumerated() { try storeAudio(key, paragraph: i, text: text, voice: voice) }
    }
}
