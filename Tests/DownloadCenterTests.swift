import SwiftData
import XCTest
@testable import MeridianReader

/// Downloads (decision D16) against the real render queue and a fake on-device voice: a page, a
/// book's chapters and a link page get their whole audio in the download voice, one page at a
/// time, behind what plays; pausing, removing, what leaves the Library leaving the list, a voice
/// change (*Different voice*, *Keep*, *Re-download*) and the background (nothing new starts).
@MainActor
final class DownloadCenterTests: XCTestCase {
    private var env: DownloadTestEnvironment!

    override func setUp() async throws {
        env = try await DownloadTestEnvironment()
    }

    override func tearDown() async throws {
        env.cleanUp()
        env = nil
    }

    private var center: DownloadCenter { env.center }
    private var library: LibraryStore { env.library }
    private var tts: LocalTTSCoordinator { env.tts }

    // MARK: - A page

    func testAPageGetsItsWholeAudioInTheDownloadVoice() async throws {
        let page = try env.savedPage("https://example.com/tides", paragraphs: env.paragraphs(4))
        XCTAssertFalse(env.isReady(page))

        XCTAssertEqual(center.download(page), .added)
        XCTAssertEqual(center.overview.queued.map(\.record.title), ["Article"])
        XCTAssertNotNil(center.overview.progress, "the progress line shows while it runs")

        try await env.waitUntil { self.center.overview.done.count == 1 }
        XCTAssertTrue(env.isReady(page))
        let item = try XCTUnwrap(center.overview.done.first)
        XCTAssertEqual(item.voice, "fake.alpha")
        XCTAssertEqual(tts.voiceLabel(forCacheVoice: "fake.alpha"), "Fake Alpha")
        XCTAssertNil(center.overview.progress, "the line goes once nothing is queued")
        XCTAssertEqual(center.download(page), .added, "asked again: queued afresh")
    }

    func testAPageAlreadyRenderedIsDoneWithoutAModelCall() async throws {
        let page = try env.savedPage("https://example.com/ready")
        tts.startBakeIfNeeded(articleID: page.listenKey, paragraphs: page.listenDocument().paragraphs)
        try await env.waitForQueueIdle()
        XCTAssertTrue(env.isReady(page))
        let calls = env.provider.lastHost?.calls.count

        _ = center.download(page)
        try await env.waitUntil { self.center.overview.done.count == 1 }
        XCTAssertEqual(env.provider.lastHost?.calls.count, calls)
    }

    // MARK: - A book

    /// The chapters that play and aren't finished, in order, one page at a time.
    func testABookDownloadsItsChaptersThatPlayInOrder() async throws {
        let book = Folder(name: "The Book", kind: .book)
        env.context.insert(book)
        var chapters: [Page] = []
        for (n, title) in ["Title Page", "One", "Two", "Three"].enumerated() {
            let page = try env.savedPage("https://example.com/book/\(n)", title: title, paragraphs: env.paragraphs(2, tag: title))
            page.setFolder(book)
            page.sortKey = Double(n)
            chapters.append(page)
        }
        chapters[0].skipsInPlayback = true
        chapters[1].finishedAt = env.now
        try env.context.save()
        env.clearCalls()

        XCTAssertEqual(center.download(book), .added)
        let record = try XCTUnwrap(center.record(for: .folder(book.id)))
        XCTAssertEqual(record.entries.map(\.key), [chapters[2].listenKey, chapters[3].listenKey],
                       "front matter and finished chapters aren't downloaded")
        try await env.waitUntil { self.center.active != nil }
        XCTAssertEqual(center.active?.key, chapters[2].listenKey, "one page at a time")
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: chapters[3].listenKey))

        try await env.waitUntil { self.center.overview.done.count == 1 }
        XCTAssertTrue(env.isReady(chapters[2]))
        XCTAssertTrue(env.isReady(chapters[3]))
        XCTAssertFalse(env.isReady(chapters[1]))
        let order = env.renderedTexts().map { $0.contains("Two") ? 2 : 3 }
        XCTAssertEqual(order, order.sorted(), "chapter Two renders before chapter Three")
    }

    // MARK: - A link page

    func testALinkPageIsFetchedAndSavedInPlace() async throws {
        let folder = try library.makeFolder(name: "Reading", in: nil)
        let url = URL(string: "https://example.com/link")!
        let link = try library.addLink(url: url, title: "A Link", artwork: nil, in: folder)
        env.fetched[url] = env.paragraphs(3, tag: "Fetched")

        _ = center.download(link)
        try await env.waitUntil { self.center.overview.done.count == 1 }

        let page = try XCTUnwrap(library.page(url: url))
        XCTAssertTrue(page.isSaved, "saved in place")
        XCTAssertIdentical(page.folder, folder)
        XCTAssertEqual(page.listenDocument().paragraphs, env.paragraphs(3, tag: "Fetched"))
        XCTAssertTrue(env.isReady(page))
    }

    func testAFetchThatFailsMarksThePageAndMovesOn() async throws {
        let folder = try library.makeFolder(name: "Reading", in: nil)
        let broken = try library.addLink(url: URL(string: "https://example.com/broken")!, title: "Broken", artwork: nil, in: folder)
        broken.sortKey = 0
        let fine = try env.savedPage("https://example.com/fine")
        fine.setFolder(folder)
        fine.sortKey = 1
        try env.context.save()

        _ = center.download(folder)
        try await env.waitUntil { self.center.overview.done.count == 1 }
        let record = try XCTUnwrap(center.record(for: .folder(folder.id)))
        XCTAssertEqual(record.entries.map(\.state), [.failed, .done])
        XCTAssertEqual(record.entries.first?.failure, "Couldn’t get the page")
        XCTAssertTrue(broken.isLink, "nothing saved")
        XCTAssertTrue(env.isReady(fine))
    }

    // MARK: - Behind what plays

    func testADownloadWaitsBehindTheArticleThatPlays() async throws {
        env.provider.config.latency = 0.02
        let playing = UUID()
        tts.synthQueue.enqueue(cacheKey: playing, paragraphs: env.paragraphs(30, tag: "Playing"), isEphemeral: false, at: .front)
        let page = try env.savedPage("https://example.com/later")

        _ = center.download(page)
        try await env.waitUntil { self.tts.synthQueue.hasJob(cacheKey: page.listenKey) }
        XCTAssertEqual(tts.synthQueue.primaryCacheKey, playing, "the playhead's article stays first")
        XCTAssertFalse(env.isReady(page))
        tts.synthQueue.remove(cacheKey: playing)
        try await env.waitUntil { self.center.overview.done.count == 1 }
    }

    /// A download queued before listening starts, then a chapter played from its middle with the
    /// next chapter staged: the playhead to the chapter's end, the next chapter's opening, the
    /// paragraphs above the playhead, and only then the download.
    func testTheCurrentChapterAndWhatComesNextRenderBeforeADownloadQueuedFirst() async throws {
        func text(_ tag: String, _ count: Int) -> [String] { (0..<count).map { "\(tag) \($0) ends." } }
        let queue = tts.synthQueue
        queue.isHeldForLaunch = true // the queue's shape first, then let it run
        let page = try env.savedPage("https://example.com/first-in-line", paragraphs: text("Download", 3))
        XCTAssertEqual(center.download(page), .added)
        try await env.waitUntil { queue.hasJob(cacheKey: page.listenKey) }
        XCTAssertEqual(queue.primaryCacheKey, page.listenKey, "nothing else was queued")

        let chapter = UUID(), next = UUID()
        env.clearCalls()
        tts.openArticle(cacheKey: chapter, paragraphs: text("Chapter", 4), from: 2, isEphemeral: false)
        XCTAssertTrue(tts.stageNextChapter(cacheKey: next, after: chapter, paragraphs: text("Next", 5)))
        queue.isHeldForLaunch = false
        try await env.waitUntil { self.center.overview.done.count == 1 }

        XCTAssertEqual(env.renderedTexts(), [
            "Chapter 2 ends.", "Chapter 3 ends.",
            "Next 0 ends.", "Next 1 ends.", "Next 2 ends.",
            "Chapter 0 ends.", "Chapter 1 ends.",
            "Download 0 ends.", "Download 1 ends.", "Download 2 ends.",
        ])
        queue.remove(cacheKey: next)
    }

    // MARK: - Pause, remove

    func testPausingTakesTheJobOutAndResumingFinishes() async throws {
        env.provider.config.latency = 0.05
        let page = try env.savedPage("https://example.com/pause", paragraphs: env.paragraphs(12))
        _ = center.download(page)
        let id = try XCTUnwrap(center.record(for: .page(page.listenKey))?.id)
        try await env.waitUntil { self.center.active != nil }

        center.setPaused(id, true)
        XCTAssertNil(center.active)
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: page.listenKey))
        if case .paused = center.overview.queued.first?.status {} else { XCTFail("shows as paused") }
        XCTAssertNil(center.overview.progress, "no line while everything is paused")

        XCTAssertEqual(center.download(page), .resumed)
        try await env.waitUntil(timeout: 30) { self.center.overview.done.count == 1 }
        XCTAssertTrue(env.isReady(page))
    }

    func testRemovingADownloadDeletesItsAudioButNotWhatYouHear() async throws {
        let heard = try env.savedPage("https://example.com/heard")
        let other = try env.savedPage("https://example.com/other")
        let folder = try library.makeFolder(name: "Two", in: nil)
        heard.setFolder(folder)
        other.setFolder(folder)
        try env.context.save()
        _ = center.download(folder)
        try await env.waitUntil { self.center.overview.done.count == 1 }
        env.listening = heard.listenKey

        center.remove(try XCTUnwrap(center.record(for: .folder(folder.id))?.id))
        XCTAssertTrue(center.overview.isEmpty)
        XCTAssertTrue(tts.hasListenAudio(for: heard.listenKey), "what you hear keeps its audio")
        XCTAssertFalse(tts.hasListenAudio(for: other.listenKey))
        XCTAssertTrue(other.isSaved, "the page stays in the Library")
    }

    // MARK: - Leaving the Library

    private struct SaveFailed: Error {}

    /// *Remove from Library* on a downloaded page: its download leaves the list at once. Its audio
    /// stays, ephemeral: the library's to keep for what plays.
    func testAPageRemovedFromTheLibraryLeavesTheListAndKeepsItsAudio() async throws {
        let page = try env.savedPage("https://example.com/removed")
        _ = center.download(page)
        try await env.waitUntil { self.center.overview.done.count == 1 }

        try library.remove([page])
        XCTAssertTrue(center.overview.isEmpty, "off the list")
        XCTAssertNil(center.record(for: .page(page.listenKey)))
        XCTAssertTrue(tts.hasListenAudio(for: page.listenKey), "its audio is kept, ephemeral")
    }

    /// A deleted folder's download leaves the list once the delete is stored.
    func testADeletedFolderLeavesTheList() async throws {
        let page = try env.savedPage("https://example.com/in-folder")
        let folder = try library.makeFolder(name: "Gone", in: nil)
        page.setFolder(folder)
        try env.context.save()
        _ = center.download(folder)
        try await env.waitUntil { self.center.overview.done.count == 1 }

        try library.deleteFolders([folder])
        XCTAssertTrue(center.overview.isEmpty)
    }

    /// A remove that can't be stored changes nothing: the download stays.
    func testARemoveThatCantBeStoredKeepsTheDownload() async throws {
        let page = try env.savedPage("https://example.com/kept-download")
        _ = center.download(page)
        try await env.waitUntil { self.center.overview.done.count == 1 }

        library.saveContext = { _ in throw SaveFailed() }
        XCTAssertThrowsError(try library.remove([page]))
        XCTAssertEqual(center.overview.done.map(\.record.target), [.page(page.listenKey)])
    }

    /// A folder's page removed from the Library before its turn isn't downloaded: it fails as no
    /// longer in the Library, and the folder's download goes on.
    func testAFolderPageRemovedFromTheLibraryIsntDownloaded() async throws {
        let kept = try env.savedPage("https://example.com/kept-page", title: "Kept")
        let removed = try env.savedPage("https://example.com/removed-page", title: "Removed")
        let folder = try library.makeFolder(name: "Two", in: nil)
        kept.setFolder(folder)
        removed.setFolder(folder)
        try env.context.save()
        env.runState.set(.background)
        _ = center.download(folder)

        try library.remove([removed])
        XCTAssertNotNil(center.record(for: .folder(folder.id)), "the folder is still in the Library")
        env.runState.set(.active)
        try await env.waitUntil { self.center.overview.done.count == 1 }
        let record = try XCTUnwrap(center.record(for: .folder(folder.id)))
        XCTAssertEqual(record.entries.first { $0.key == removed.listenKey }?.failure, "It’s no longer in the Library")
        XCTAssertEqual(record.entries.first { $0.key == kept.listenKey }?.state, .done)
    }

    // MARK: - The voice

    func testAVoiceChangeMarksDownloadsAsADifferentVoiceUntilKeptOrDownloadedAgain() async throws {
        let page = try env.savedPage("https://example.com/voices")
        _ = center.download(page)
        try await env.waitUntil { self.center.overview.done.count == 1 }

        tts.setVoice("beta", for: FakeEngineProvider.fakeID)
        XCTAssertEqual(tts.downloadVoice, "fake.beta")
        let different = try XCTUnwrap(center.overview.differentVoice.first)
        XCTAssertEqual(different.voice, "fake.alpha", "named by the voice its audio is in")
        XCTAssertTrue(center.overview.done.isEmpty)

        center.keep(different.id, voice: "fake.alpha")
        XCTAssertEqual(center.overview.done.first?.voice, "fake.alpha", "kept: done, still named by its voice")
        XCTAssertTrue(center.overview.differentVoice.isEmpty)

        center.redownload(different.id)
        try await env.waitUntil(timeout: 30) { self.center.overview.done.first?.voice == "fake.beta" }
        XCTAssertTrue(env.isReady(page))
    }

    func testWithApplesVoiceDownloadsWaitForAnOnDeviceVoice() async throws {
        let page = try env.savedPage("https://example.com/apple")
        await tts.selectEngine(.apple)
        XCTAssertFalse(tts.wantsLocalBake)
        XCTAssertEqual(tts.downloadVoice, "fake.alpha", "still names the voice downloads will use")

        _ = center.download(page)
        if case .waitingForVoice = center.overview.queued.first?.status {} else { XCTFail("waits for a voice") }
        XCTAssertNil(center.overview.progress)

        await tts.selectEngine(FakeEngineProvider.fakeID)
        try await env.waitUntil { self.center.overview.done.count == 1 }
    }

    // MARK: - The background

    func testNothingNewStartsInTheBackground() async throws {
        let page = try env.savedPage("https://example.com/bg")
        env.runState.set(.background)

        _ = center.download(page)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(center.active)
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: page.listenKey))

        env.runState.set(.active)
        try await env.waitUntil { self.center.overview.done.count == 1 }
    }

    /// On a route that renders in the background (Kokoro's ONNX route), only the article playing
    /// renders there, in bursts: a download's job parks after the chunk in flight, and goes on in
    /// front.
    func testADownloadParksInTheBackgroundOnARouteThatRendersThere() async throws {
        env.provider.config.rendersInBackground = true
        env.provider.config.latency = 0.03
        await tts.selectEngine(.apple)
        await tts.selectEngine(FakeEngineProvider.fakeID)  // a host with the new config
        XCTAssertTrue(tts.activeRouteRendersInBackground)
        let page = try env.savedPage("https://example.com/parks", paragraphs: env.paragraphs(20))
        _ = center.download(page)
        try await env.waitUntil { (self.env.provider.lastHost?.calls.count ?? 0) > 1 }

        env.runState.set(.background)
        try await env.waitUntil { !self.tts.synthQueue.isWorkerRunning }
        let parked = env.provider.lastHost?.calls.count
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(env.provider.lastHost?.calls.count, parked, "nothing renders for a download in the background")
        XCTAssertFalse(env.isReady(page))

        env.runState.set(.active)
        try await env.waitUntil(timeout: 30) { self.center.overview.done.count == 1 }
    }

    // MARK: - Kept on the device

    func testTheListOutlivesARelaunch() async throws {
        let page = try env.savedPage("https://example.com/kept")
        _ = center.download(page)
        try await env.waitUntil { self.center.overview.done.count == 1 }
        let again = env.makeCenter()
        again.start()
        XCTAssertEqual(again.records, center.records)
    }
}

/// A library and a download list over a fake on-device voice ("Fake", voices Alpha and Beta),
/// in a temporary directory.
@MainActor
final class DownloadTestEnvironment {
    let dir: URL
    let container: ModelContainer
    let provider: FakeEngineProvider
    let tts: LocalTTSCoordinator
    let library: LibraryStore
    let runState = AppRunState(phase: .active)
    private let suite: String
    private(set) var center: DownloadCenter!
    /// What the fake fetcher returns, by address; any other address fails.
    var fetched: [URL: [String]] = [:]
    /// The page "you hear".
    var listening: UUID?
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var callsBefore = 0

    init() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "Downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        container = try LibraryStoreConfiguration.makeInMemoryContainer()
        suite = "Downloads-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(FakeEngineProvider.fakeID.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        provider = FakeEngineProvider()
        provider.voices = [EngineVoice(id: "alpha", label: "Alpha"), EngineVoice(id: "beta", label: "Beta")]
        provider.defaultVoice = "alpha"
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), provider], gate: { _ in true })
        tts = LocalTTSCoordinator(engines: registry, defaults: defaults,
                                  audioCache: ArticleAudioCache(root: dir.appending(path: "TTSCache")),
                                  crashGuard: EngineCrashGuard(directory: dir.appending(path: "guard")))
        tts.synthQueue.runState = runState
        library = LibraryStore(context: container.mainContext, tts: tts, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        await tts.selectEngine(FakeEngineProvider.fakeID)
        center = makeCenter()
        center.start()
    }

    func makeCenter() -> DownloadCenter {
        DownloadCenter(library: library, tts: tts, store: DownloadListStore(url: dir.appending(path: "Downloads.json")),
                       runState: runState,
                       fetch: { [unowned self] url in
                           guard let paragraphs = fetched[url] else { throw URLError(.cannotConnectToHost) }
                           return PageContent(ref: PageRef(key: ArticleIdentity.articleKey(url: url), locator: .web(url), ordinal: 0),
                                              title: "Fetched Title", bodyHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                              plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
                       },
                       save: { [unowned self] article in
                           try library.save(article).listenKey
                       },
                       isListening: { [unowned self] in $0 == listening })
    }

    var context: ModelContext { container.mainContext }

    func cleanUp() {
        // The pending-job file is the app's own: only this test's pages leave it.
        for page in (try? context.fetch(FetchDescriptor<Page>())) ?? [] {
            tts.synthQueue.remove(cacheKey: page.listenKey)
            PendingBakeJobStore.shared.removePending(articleID: page.listenKey)
        }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    func paragraphs(_ count: Int, tag: String = "Tides") -> [String] {
        (1...count).map { "\(tag) paragraph \($0) has a sentence in it." }
    }

    /// A saved page in no folder (its save queues its bake, as in the app).
    @discardableResult
    func savedPage(_ url: String, title: String = "Article", paragraphs: [String]? = nil) throws -> Page {
        let paragraphs = paragraphs ?? self.paragraphs(2)
        let u = URL(string: url)!
        let extracted = ExtractedArticle(title: title, siteName: nil, cleanedHTML: paragraphs.map { "<p>\($0)</p>" }.joined(),
                                         plainText: paragraphs.joined(separator: "\n\n"), excerpt: "")
        let article = library.readerArticle(url: u, extracted: extracted)
        return try library.save(article)
    }

    func isReady(_ page: Page) -> Bool {
        tts.missingDownloadParagraphs(cacheKey: page.listenKey, paragraphs: page.listenDocument().paragraphs) == 0
    }

    func clearCalls() { callsBefore = provider.lastHost?.calls.count ?? 0 }

    /// Texts rendered since `clearCalls`, in order.
    func renderedTexts() -> [String] {
        Array((provider.lastHost?.calls ?? []).dropFirst(callsBefore).map(\.text))
    }

    func waitForQueueIdle(timeout: TimeInterval = 20) async throws {
        try await waitUntil(timeout: timeout) { !self.tts.synthQueue.isWorkerRunning }
    }

    func waitUntil(timeout: TimeInterval = 20, _ condition: @escaping () -> Bool) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 20_000_000)
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("timed out")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
