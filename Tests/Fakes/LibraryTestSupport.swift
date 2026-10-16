import Foundation
import SwiftData
@testable import MeridianReader

/// A library over an in-memory container, with a clock the test sets. Its audio effects go to a
/// real coordinator (Apple's engine only) whose files sit in a temp directory and whose settings
/// sit in a defaults suite of its own. `cleanUp()` removes them.
@MainActor
final class LibraryTestEnvironment {
    let dir: URL
    let container: ModelContainer
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let suite = "LibraryTest-\(UUID().uuidString)"
    private(set) var library: LibraryStore!

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LibraryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        container = try LibraryStoreConfiguration.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: suite)!
        let tts = LocalTTSCoordinator(
            engines: EngineRegistry(providers: [AppleSpeechProvider()], gate: { _ in true }), defaults: defaults,
            audioCache: ArticleAudioCache(root: dir.appending(path: "TTSCache")),
            crashGuard: EngineCrashGuard(directory: dir.appending(path: "guard")),
            pendingBakes: PendingBakeJobStore(storeURL: dir.appending(path: "PendingBakeJobs.json"), defaults: defaults),
            resumePoints: ListenResumePointStore(url: dir.appending(path: "listen_resume.json")))
        let legacy = LegacyLibrarySources(bookmarksURL: dir.appending(path: "bookmarks.json"), defaults: defaults)
        library = LibraryStore(context: container.mainContext, audio: tts, legacy: legacy, now: { [unowned self] in now })
    }

    var context: ModelContext { container.mainContext }

    func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    /// A reader article for `url` with two short paragraphs.
    func article(_ url: String, title: String = "Title") -> ReaderArticle {
        let u = URL(string: url)!
        let paragraphs = ["First paragraph here.", "Second paragraph here."]
        let extracted = ExtractedArticle(title: title, siteName: nil, cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
        return ReaderArticle(id: ArticleIdentity.articleKey(url: u), url: u, extracted: extracted)
    }
}
