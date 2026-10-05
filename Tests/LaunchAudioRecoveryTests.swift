import SwiftData
import XCTest
@testable import Reader

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
        PendingBakeJobStore.shared.enqueuePending(articleID: chapter, paragraphs: old, voiceID: "voiceA",
                                                  plan: .topDown(paragraphCount: old.count))

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
        let plan = try XCTUnwrap(tts.synthQueue.planDescription(for: chapter), "the chapter's pending render was adopted")
        XCTAssertTrue(plan.contains("paragraphCount: \(new.count)"), "on the new paragraphs: \(plan)")
        XCTAssertFalse(tts.synthQueue.hasJob(cacheKey: played))
    }
}
