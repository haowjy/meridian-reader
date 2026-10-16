import SwiftData
import XCTest
@testable import MeridianReader

/// The launch finishes the audio work an earlier launch left before anything cleans, reads or
/// renders the audio cache. Driven through the composition's launch step
/// (`AppComposition.prepareAudioCache`, which `ReaderApp.init` runs), not a direct call.
@MainActor
final class LaunchAudioRecoveryTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var keys: [UUID] = []
    private struct Died: Error {}

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }
    override func tearDown() async throws {
        for key in keys { PendingBakeJobStore.shared.removePending(articleID: key) }
        env.cleanUp()
    }

    /// A one-time launch step that only looks.
    private struct Probe: LaunchMigration {
        let look: (LocalTTSCoordinator) -> Void
        func runIfNeeded(_ tts: LocalTTSCoordinator) { look(tts) }
    }

    private func work() -> Int { (try? env.context.fetch(FetchDescriptor<LibraryAudioWork>()).count) ?? -1 }

    /// The bytes of each CAF a key's audio directory holds.
    private func audio(_ key: UUID) -> Set<Data> {
        let dir = env.cache.directory(for: key)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".caf") }.compactMap { try? Data(contentsOf: dir.appending(path: $0)) })
    }

    private func page(_ key: UUID, _ url: String, paragraphs: [String], added: Date?, position: Int) -> Page {
        let page = Page(key: key, title: "Article", byline: "example.com", urlString: url, contentState: .saved, addedAt: added)
        page.canonicalURL = "https://example.com/article"
        page.cleanedHTML = paragraphs.map { "<p>\($0)</p>" }.joined()
        page.storeListenParagraphs(paragraphs)
        page.positionParagraph = position
        env.context.insert(page)
        return page
    }

    /// An earlier launch saved the layout pass (a chapter on the pre-split blocks, with a pending
    /// render) and a dedupe merge (a page played without saving, whose audio is unsaved and 30
    /// days old, into the saved page for its address), then died in their audio work. The next
    /// launch, as the app runs it: the speech stack first (its engine starts loading), then the
    /// composition's launch step. The merge is done before the launch migrations run and before
    /// the prune, which would otherwise have deleted the merged audio as old unsaved audio; and
    /// the engine, once loaded, adopts the chapter's pending render on its new paragraphs.
    func testTheLaunchFinishesLeftAudioWorkBeforeTheCacheIsCleanedOrBakesAreAdopted() async throws {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let old = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false).paragraphs
        let new = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title).paragraphs
        XCTAssertNotEqual(old.count, new.count)
        let chapter = UUID(), saved = UUID(), played = UUID()
        keys = [chapter, saved, played]
        let page = Page(key: chapter, title: title, byline: "example.com", urlString: "https://example.com/classics/boscombe-valley",
                        contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.listenBlocksData = try JSONEncoder().encode(old)
        page.listenBlocksVersion = 2
        page.paragraphCount = old.count
        env.context.insert(page)
        let last = old.count - 1
        try env.storeAudio(chapter, paragraph: last, text: old[last], level: 0.2)
        PendingBakeJobStore.shared.enqueuePending(articleID: chapter, paragraphs: old, priorityStart: 0)

        let text = ["One paragraph.", "Two paragraphs."]
        _ = self.page(saved, "https://example.com/article", paragraphs: text, added: env.now, position: 1)
        _ = self.page(played, "https://example.com/article?utm_source=feed", paragraphs: text, added: nil, position: 0)
        try env.context.save()
        for (i, line) in text.enumerated() { try env.storeAudio(played, paragraph: i, text: line, level: 0.3 + Float(i) / 10) }
        env.cache.markEphemeral(cacheKey: played, lastAccess: Date().addingTimeInterval(-30 * 24 * 3600))

        env.cache.faultHook = { _ in throw Died() }
        env.library.migrateParagraphLayout()
        XCTAssertEqual(env.library.dedupe().mergedPages, 1)
        XCTAssertEqual(work(), 2, "both saved, neither done")

        // Next launch. The stored engine is the on-device one, so the coordinator starts loading it.
        env.defaults.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        try env.relaunch()
        let tts = env.tts
        XCTAssertNotNil(tts.synth.state.warmingEngineID, "loading, as at app launch")
        // Hold rendering, so the adopted job stays as it was adopted.
        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false) }
        var seen: (work: Int, merged: Bool)?
        let probe = Probe { tts in
            seen = (self.work(), tts.audioCache.index(for: saved)?.paragraphs.count == text.count)
        }
        AppComposition.prepareAudioCache(library: env.library, migrations: [probe])

        XCTAssertEqual(seen?.work, 0, "the launch migrations run after the left work is done")
        XCTAssertEqual(seen?.merged, true, "and find the merged audio under the saved page")
        XCTAssertEqual(work(), 0)
        let cold = ArticleAudioCache(root: env.cache.root)
        XCTAssertEqual(cold.index(for: saved)?.paragraphs.map(\.textHash), text.map(ArticleIdentity.paragraphHash),
                       "the prune didn't delete the merged audio first")
        XCTAssertFalse(cold.hasDirectory(for: played))
        XCTAssertEqual(cold.entry(articleID: chapter, paragraphIndex: new.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(old[last]), "the chapter's audio is on its new paragraph")

        for _ in 0..<200 where !tts.usesLocalEngine { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(tts.usesLocalEngine, "the engine finished loading after the launch step")
        AppLaunch.maintainLibrary(env.library)
        let plan = try XCTUnwrap(tts.synthQueue.planDescription(for: chapter), "the chapter's pending render was adopted")
        XCTAssertTrue(plan.contains("paragraphCount: \(new.count)"), "on the new paragraphs: \(plan)")
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: played))
    }

    /// An earlier launch saved a dedupe merge (a page played without saving, whose audio is
    /// unsaved and 30 days old, into the saved page for its address) and died in its audio work.
    /// The next launch can't finish it either: copying the merged audio fails (a full disk, say).
    /// The work holds both pages' audio: the launch's engine purge and the prune leave it alone
    /// (the purge runs again next launch), and the kept page's pending render isn't adopted. A
    /// later launch that can copy finishes the merge with all of the merged audio.
    func testWorkThatFailsAtLaunchHoldsItsAudioFromTheCleanupAndBakes() async throws {
        let text = ["One paragraph.", "Two paragraphs."]
        let saved = UUID(), played = UUID()
        keys = [saved, played]
        _ = page(saved, "https://example.com/article", paragraphs: text, added: env.now, position: 1)
        _ = page(played, "https://example.com/article?utm_source=feed", paragraphs: text, added: nil, position: 0)
        try env.context.save()
        for (i, line) in text.enumerated() { try env.storeAudio(played, paragraph: i, text: line, level: 0.3 + Float(i) / 10) }
        env.cache.markEphemeral(cacheKey: played, lastAccess: Date().addingTimeInterval(-30 * 24 * 3600))
        let merged = audio(played)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(env.cache.index(for: played)?.engineID, SpeechEngineID.kokoro.rawValue, "audio the Kokoro purge would take")
        PendingBakeJobStore.shared.enqueuePending(articleID: saved, paragraphs: text, priorityStart: 0)
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertEqual(env.library.dedupe().mergedPages, 1)
        XCTAssertEqual(work(), 1, "saved, not done")

        // Next launch: a Kokoro audio purge is due, and every copy fails.
        env.defaults.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        env.defaults.set(KokoroAudioCachePurge.version - 1, forKey: KokoroAudioCachePurge.versionKey)
        try env.relaunch()
        let tts = env.tts
        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false) }
        tts.audioCache.faultHook = { if $0 == .wroteFile { throw Died() } }
        AppComposition.prepareAudioCache(library: env.library, migrations: [KokoroAudioCachePurge()])

        XCTAssertEqual(work(), 1, "the merge still waits")
        XCTAssertEqual(tts.audioCache.held, .pages([saved, played]))
        XCTAssertEqual(audio(played), merged, "neither the purge nor the prune took the merged audio")
        XCTAssertEqual(env.cache.loadMeta(for: played)?.kind, .ephemeral)
        XCTAssertEqual(env.defaults.integer(forKey: KokoroAudioCachePurge.versionKey), KokoroAudioCachePurge.version - 1,
                       "the purge runs again once nothing is held")
        for _ in 0..<200 where !tts.usesLocalEngine { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(tts.usesLocalEngine)
        AppLaunch.maintainLibrary(env.library)
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: saved), "the kept page's pending render waits")
        XCTAssertTrue(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == saved }, "on disk")

        // A later launch can copy.
        try env.relaunch()
        AppComposition.prepareAudioCache(library: env.library, migrations: [])
        XCTAssertEqual(work(), 0)
        XCTAssertEqual(env.tts.audioCache.held, .nothing)
        XCTAssertFalse(env.cache.hasDirectory(for: played))
        XCTAssertEqual(audio(saved), merged, "the kept page has all of the merged audio")
        env.tts.endLaunchHold()
    }

    /// An earlier launch saved a dedupe merge (a page played without saving, whose audio is
    /// unsaved and 30 days old, into the saved page for its address) and died in its audio work.
    /// The next launch can't read the stored work at all, so it can't tell which pages' audio it
    /// needs: it holds everything. The engine purge and the prune leave the merged audio alone
    /// (the purge runs again next launch), and no pending render is adopted, the merged page's
    /// and the kept page's included. A later launch that can read the work finishes the merge.
    func testUnreadableWorkHoldsAllAudioFromTheCleanupAndBakes() async throws {
        let text = ["One paragraph.", "Two paragraphs."]
        let saved = UUID(), played = UUID()
        keys = [saved, played]
        _ = page(saved, "https://example.com/article", paragraphs: text, added: env.now, position: 1)
        _ = page(played, "https://example.com/article?utm_source=feed", paragraphs: text, added: nil, position: 0)
        try env.context.save()
        for (i, line) in text.enumerated() { try env.storeAudio(played, paragraph: i, text: line, level: 0.3 + Float(i) / 10) }
        env.cache.markEphemeral(cacheKey: played, lastAccess: Date().addingTimeInterval(-30 * 24 * 3600))
        let merged = audio(played)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(env.cache.index(for: played)?.engineID, SpeechEngineID.kokoro.rawValue, "audio the Kokoro purge would take")
        for key in [saved, played] {
            PendingBakeJobStore.shared.enqueuePending(articleID: key, paragraphs: text, priorityStart: 0)
        }
        env.cache.faultHook = { _ in throw Died() }
        XCTAssertEqual(env.library.dedupe().mergedPages, 1)
        XCTAssertEqual(work(), 1, "saved, not done")

        // Next launch: a Kokoro audio purge is due, and the stored work can't be read.
        env.defaults.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        env.defaults.set(KokoroAudioCachePurge.version - 1, forKey: KokoroAudioCachePurge.versionKey)
        try env.relaunch()
        let tts = env.tts
        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false) }
        env.library.fetchAudioWork = { _ in throw Died() }
        AppComposition.prepareAudioCache(library: env.library, migrations: [KokoroAudioCachePurge()])

        XCTAssertEqual(work(), 1, "the merge still waits")
        XCTAssertEqual(tts.audioCache.held, .all)
        XCTAssertEqual(audio(played), merged, "neither the purge nor the prune took the merged audio")
        XCTAssertEqual(env.cache.loadMeta(for: played)?.kind, .ephemeral)
        XCTAssertEqual(env.defaults.integer(forKey: KokoroAudioCachePurge.versionKey), KokoroAudioCachePurge.version - 1,
                       "the purge runs again once the work can be read")
        for _ in 0..<200 where !tts.usesLocalEngine { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(tts.usesLocalEngine)
        AppLaunch.maintainLibrary(env.library)
        for key in [saved, played] {
            XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: key), "a pending render waits while the work can't be read")
            XCTAssertTrue(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == key }, "on disk")
        }

        // A later launch can read it.
        try env.relaunch()
        AppComposition.prepareAudioCache(library: env.library, migrations: [])
        XCTAssertEqual(work(), 0)
        XCTAssertEqual(env.tts.audioCache.held, .nothing)
        XCTAssertFalse(env.cache.hasDirectory(for: played))
        XCTAssertEqual(audio(saved), merged, "the kept page has all of the merged audio")
        env.tts.endLaunchHold()
    }

    /// This launch's own layout pass rebuilds a chapter that has a pending render, and the engine
    /// finished loading before that pass ran. The render queue is held from the launch's first
    /// audio step until the library's launch maintenance has finished (`AppLaunch`): the loaded
    /// engine adopts nothing meanwhile, then adopts the chapter's render on its new paragraphs.
    func testBakesAreAdoptedOnlyOnceThisLaunchsMaintenanceHasFinished() async throws {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let old = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false).paragraphs
        let new = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title).paragraphs
        let chapter = UUID()
        keys = [chapter]
        let page = Page(key: chapter, title: title, byline: "example.com", urlString: "https://example.com/classics/boscombe-valley",
                        contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.listenBlocksData = try JSONEncoder().encode(old)
        page.listenBlocksVersion = 2
        page.paragraphCount = old.count
        env.context.insert(page)
        try env.context.save()
        PendingBakeJobStore.shared.enqueuePending(articleID: chapter, paragraphs: old, priorityStart: 0)

        env.defaults.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        try env.relaunch()
        let tts = env.tts
        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false) }
        AppComposition.prepareAudioCache(library: env.library, migrations: [])
        for _ in 0..<200 where !tts.usesLocalEngine { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(tts.usesLocalEngine, "the engine loaded before the launch's maintenance ran")
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: chapter), "nothing adopted while the launch holds the queue")

        AppLaunch.maintainLibrary(env.library)
        XCTAssertEqual(env.library.page(key: chapter)?.cachedListenParagraphs, new, "the layout pass rebuilt the chapter")
        let plan = try XCTUnwrap(tts.synthQueue.planDescription(for: chapter), "adopted once the maintenance finished")
        XCTAssertTrue(plan.contains("paragraphCount: \(new.count)"), "on the new paragraphs: \(plan)")
    }

    /// The launch's maintenance can't save anything: the layout pass and the prune are rolled
    /// back. It still ends the launch hold: the queue adopts the saved bake jobs as they are (the
    /// chapter's on its old paragraphs, which the page still holds) and is free to render.
    func testTheLaunchHoldEndsWhenTheMaintenanceCantSave() async throws {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let old = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false).paragraphs
        let chapter = UUID(), stale = UUID()
        keys = [chapter]
        let page = Page(key: chapter, title: title, byline: "example.com", urlString: "https://example.com/classics/boscombe-valley",
                        contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.listenBlocksData = try JSONEncoder().encode(old)
        page.listenBlocksVersion = 2
        page.paragraphCount = old.count
        env.context.insert(page)
        let unsaved = self.page(stale, "https://example.com/old-news", paragraphs: ["Old news."], added: nil, position: 0)
        unsaved.canonicalURL = "https://example.com/old-news"
        unsaved.lastPlayedAt = env.now.addingTimeInterval(-30 * 24 * 3600)
        try env.context.save()
        PendingBakeJobStore.shared.enqueuePending(articleID: chapter, paragraphs: old, priorityStart: 0)

        env.defaults.set(SpeechEngineID.kokoro.rawValue, forKey: LocalTTSCoordinator.engineIDKey)
        try env.relaunch()
        let tts = env.tts
        tts.synthQueue.bakeConditions = { BakeConditions(thermalState: .serious, isLowPowerModeEnabled: false) }
        AppComposition.prepareAudioCache(library: env.library, migrations: [])
        for _ in 0..<200 where !tts.usesLocalEngine { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(tts.usesLocalEngine, "the engine loaded before the launch's maintenance ran")
        env.library.saveContext = { _ in throw Died() }
        AppLaunch.maintainLibrary(env.library)

        XCTAssertEqual(env.library.page(key: chapter)?.listenBlocksVersion, 2, "the layout pass was rolled back")
        XCTAssertNotNil(env.library.page(key: stale), "and so was the prune")
        XCTAssertFalse(tts.isHeldForLaunch)
        XCTAssertFalse(tts.synthQueue.isHeldForLaunch, "the queue may render")
        let plan = try XCTUnwrap(tts.synthQueue.planDescription(for: chapter), "the chapter's pending render was adopted")
        XCTAssertTrue(plan.contains("paragraphCount: \(old.count)"), "as it was saved: \(plan)")
    }
}
