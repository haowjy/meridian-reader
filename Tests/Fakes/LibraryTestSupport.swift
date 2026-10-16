import Foundation
import SwiftData
import XCTest
@testable import MeridianReader

/// A library over an in-memory container (or, `fileBacked`, the two store files), with its own
/// audio cache, defaults and bookmarks file in a temp directory. `cleanUp()` removes them.
@MainActor
final class LibraryTestEnvironment {
    let dir: URL
    private(set) var container: ModelContainer
    let fileBacked: Bool
    private(set) var tts: LocalTTSCoordinator
    let defaults: UserDefaults
    let suite: String
    let legacy: LegacyLibrarySources
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var library: LibraryStore!
    /// Keys `stopPlaybackIfPlaying` was asked about while they were "playing".
    var playingKey: UUID?
    private(set) var stoppedKeys: [UUID] = []
    /// What stopping the playing key does besides being recorded: the app's progress recorder
    /// saves the position on Stop.
    var onStop: ((UUID) -> Void)?

    init(fileBacked: Bool = false) throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LibraryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileBacked = fileBacked
        container = try Self.makeContainer(dir: dir, fileBacked: fileBacked)
        suite = "LibraryTest-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        tts = Self.makeTTS(dir: dir, defaults: defaults)
        legacy = LegacyLibrarySources(bookmarksURL: dir.appending(path: "Bookmarks/bookmarks.json"), defaults: defaults)
        library = makeLibrary()
    }

    /// The store files sit in their own folder, so a test can lock the rest of `dir`.
    var storeDirectory: URL { dir.appending(path: "Stores") }

    private static func makeContainer(dir: URL, fileBacked: Bool) throws -> ModelContainer {
        guard fileBacked else { return try LibraryStoreConfiguration.makeInMemoryContainer() }
        let stores = dir.appending(path: "Stores")
        return try LibraryStoreConfiguration.makeContainer(localURL: stores.appending(path: "default.store"),
                                                           libraryURL: stores.appending(path: "library.store"))
    }

    /// A coordinator over the audio cache in `dir/TTSCache`, its crash guard in `dir/guard`.
    static func makeTTS(dir: URL, defaults: UserDefaults) -> LocalTTSCoordinator {
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), KokoroStubProvider()], gate: { _ in true })
        return LocalTTSCoordinator(engines: registry, defaults: defaults,
                                   audioCache: ArticleAudioCache(root: dir.appending(path: "TTSCache")),
                                   crashGuard: EngineCrashGuard(directory: dir.appending(path: "guard")))
    }

    /// A relaunch from disk: a fresh container on the same store files (file-backed only), a
    /// fresh coordinator and audio cache over the same directory (nothing kept in memory), and a
    /// new library over them. Objects fetched before belong to the old container.
    func relaunch() throws {
        precondition(fileBacked, "relaunch needs the store files")
        container = try Self.makeContainer(dir: dir, fileBacked: true)
        tts = Self.makeTTS(dir: dir, defaults: defaults)
        library = makeLibrary()
    }

    /// A second store over the same container (a relaunch, as far as the library is concerned).
    func makeLibrary() -> LibraryStore {
        let store = LibraryStore(context: container.mainContext, tts: tts, legacy: legacy, now: { [unowned self] in now })
        store.stopPlaybackIfPlaying = { [unowned self] key in
            guard key == playingKey else { return }
            stoppedKeys.append(key)
            playingKey = nil
            onStop?(key)
        }
        return store
    }

    var context: ModelContext { container.mainContext }
    var cache: ArticleAudioCache { tts.audioCache }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
        ListenResumePointStore.shared.clear()
    }

    // MARK: Fixtures

    func pages() -> [Page] { (try? context.fetch(FetchDescriptor<Page>())) ?? [] }
    func receipts() -> [LibraryMigrationReceipt] { (try? context.fetch(FetchDescriptor<LibraryMigrationReceipt>())) ?? [] }
    func folders() -> [Folder] { (try? context.fetch(FetchDescriptor<Folder>())) ?? [] }

    /// The Favorites folder an older build kept, as a store it left still holds it.
    func legacyFavoritesFolder() -> Folder {
        let folder = Folder(name: "", kind: .favorites, sortKey: -1)
        context.insert(folder)
        return folder
    }

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

    /// Stores a rendered paragraph for `key` (a short tone of `level`), as a finished bake would.
    func storeAudio(_ key: UUID, paragraph: Int, text: String, voice: String = "voiceA", level: Float = 0.1) throws {
        let tmp = dir.appending(path: "tone-\(UUID().uuidString).caf")
        try LocalPCMWriter.write([Float](repeating: level, count: 2400), sampleRate: 24_000, to: tmp)
        try cache.storeParagraph(articleID: key, paragraphIndex: paragraph, sourceURL: tmp, duration: 0.1,
                                 engineID: tts.cacheEngineID, voiceID: voice, text: text)
    }

    /// Audio for every paragraph of `paragraphs`.
    func storeAudio(_ key: UUID, paragraphs: [String], voice: String = "voiceA") throws {
        for (i, text) in paragraphs.enumerated() { try storeAudio(key, paragraph: i, text: text, voice: voice) }
    }
}

extension LibraryStore {
    /// A link page for `url` in `folder` (the existing page for that address, unchanged), saved:
    /// a fixture for a page that is only an address, such as a chapter not fetched yet.
    @discardableResult
    func addLink(url: URL, title: String?, artwork: Data?, in folder: Folder?) throws -> Page {
        if let existing = page(url: url) { return existing }
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        let host = url.host ?? url.absoluteString
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try edit("add link") {
            let page = Page(key: ArticleIdentity.articleKey(canonicalURL: canonical), title: trimmed.isEmpty ? host : trimmed,
                            byline: host, urlString: url.absoluteString, contentState: .link, addedAt: now(),
                            sortKey: nextSortKey(in: folder), artworkData: artwork)
            context.insert(page)
            page.setFolder(folder)
            return page
        }
    }
}
