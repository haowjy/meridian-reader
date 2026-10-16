import SwiftData
import XCTest
@testable import MeridianReader

/// `-resetLibrary`, which every UI test launches with: what an earlier test left (a starred link,
/// a folder of saved pages and their audio, history, stored settings) is gone, so each test starts
/// the same whatever ran before it, and the seeds add to an empty library.
@MainActor
final class LaunchResetTests: XCTestCase {
    private var env: LibraryTestEnvironment!

    override func setUp() async throws { env = try LibraryTestEnvironment() }

    override func tearDown() async throws { env.cleanUp() }

    func testTheLibraryIsEmptiedBeforeTheSeedsAdd() throws {
        try env.library.addFavorite(url: URL(string: "https://example.com/starred")!, title: "Starred", artwork: nil)
        try env.library.addLink(url: URL(string: "https://example.com/link")!, title: "Link", artwork: nil, in: nil)
        let folder = try env.library.makeFolder(name: "Left Behind", in: nil)
        let saved = try env.library.save(env.article("https://example.com/saved", title: "Saved"), placement: .folder(folder))
        try env.storeAudio(saved.listenKey, paragraphs: ["First paragraph here.", "Second paragraph here."])
        env.context.insert(RecentVisit(urlString: "https://example.com/visited", title: "Visited", host: "example.com"))
        env.library.commit("an earlier test's leftovers")
        XCTAssertTrue(env.cache.hasCache(for: saved.listenKey))

        LaunchHooks.runSeeds(LaunchOptions(arguments: ["-uiTesting", "-resetLibrary", "-seedDemoArticle"]), library: env.library)

        XCTAssertEqual(env.pages().map(\.title), ["Demo Listen Article"], "link pages go too")
        XCTAssertEqual(env.folders().count, 0)
        XCTAssertEqual(try env.context.fetchCount(FetchDescriptor<RecentVisit>()), 0, "the history goes")
        XCTAssertFalse(env.cache.hasCache(for: saved.listenKey), "a deleted page's audio goes with it")
    }

    func testTheStoredSettingsGoBeforeAnythingReadsThem() throws {
        let defaults = env.defaults
        let engines = env.speech.engines
        let downloads = DownloadListStore(url: env.dir.appending(path: "Downloads.json"))
        let surface = SurfaceMemoryStore(defaults: defaults)
        defaults.set("local.kokoro", forKey: LocalTTSCoordinator.engineIDKey)
        for descriptor in engines.descriptors { defaults.set("voice", forKey: descriptor.resolvedVoiceDefaultsKey) }
        defaults.set("com.apple.voice", forKey: SpeechController.voiceDefaultsKey)
        defaults.set("fr-FR", forKey: SpeechController.languageDefaultsKey)
        defaults.set(false, forKey: SpeechController.languageAutomaticKey)
        defaults.set(2.0, forKey: SpeechController.rateDefaultsKey)
        defaults.set("title", forKey: LibraryTopLevel.sortKey)
        defaults.set("one\ntwo", forKey: RecentSearches.storageKey)
        surface.save(SurfaceMemory(base: .library, libraryPath: [], browserURL: nil))
        surface.saveFavoritesTab(true)
        downloads.save([DownloadRecord(target: .page(UUID()), title: "Queued", addedAt: Date(), entries: [.init(key: UUID())])])

        LaunchHooks.resetStoredSettings(engines: engines, defaults: defaults, downloads: downloads)

        let keys = [LocalTTSCoordinator.engineIDKey, SpeechController.voiceDefaultsKey, SpeechController.languageDefaultsKey,
                    SpeechController.languageAutomaticKey, SpeechController.rateDefaultsKey, LibraryTopLevel.sortKey,
                    RecentSearches.storageKey] + engines.descriptors.map(\.resolvedVoiceDefaultsKey)
        for key in keys { XCTAssertNil(defaults.object(forKey: key), key) }
        XCTAssertNil(surface.load(), "the remembered surface")
        XCTAssertFalse(surface.loadFavoritesTab(), "the Library's tab")
        XCTAssertEqual(downloads.load(), [], "the download list")
    }
}
