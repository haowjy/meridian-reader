import SwiftData
import XCTest
@testable import Reader

/// Files outside the library store (the audio cache, pending renders, the crash-resume point)
/// change only after the library change they belong to is saved: a failed save leaves them as
/// they were, a launch that dies after the save finishes the work next time, and work done twice
/// moves nothing twice.
@MainActor
final class LibraryAudioWorkTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }
    override func tearDown() async throws { env.cleanUp() }

    private struct SaveFailed: Error {}
    private func date(_ days: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + days * 24 * 3600) }

    /// Two saved rows for one address, both with audio; the one dedupe merges away has a pending
    /// render and the crash-resume point.
    private struct DuplicateRows {
        let merged = UUID()
        let kept = UUID()
        let mergedText = ["Alpha one.", "Beta two.", "Gamma three."]
        let keptText = ["Alpha one.", "Beta changed.", "Gamma three."]
    }

    private func duplicateRows() throws -> DuplicateRows {
        let rows = DuplicateRows()
        env.legacyRow("https://example.com/dup?utm_source=feed", id: rows.merged, savedAt: date(0), paragraphs: rows.mergedText)
        env.legacyRow("https://example.com/dup", id: rows.kept, savedAt: date(1), paragraphs: rows.keptText, position: 2)
        try env.storeAudio(rows.merged, paragraphs: rows.mergedText)
        try env.storeAudio(rows.kept, paragraph: 1, text: "Beta changed.")
        PendingBakeJobStore.shared.enqueuePending(articleID: rows.merged, paragraphs: rows.mergedText, voiceID: "voiceA",
                                                  plan: .topDown(paragraphCount: 3))
        ListenResumePointStore.shared.save(article: rows.merged, paragraph: 1, at: date(2))
        addTeardownBlock { @MainActor in
            PendingBakeJobStore.shared.removePending(articleID: rows.merged)
            PendingBakeJobStore.shared.removePending(articleID: rows.kept)
        }
        return rows
    }

    /// Every file under a key's audio directory, by relative path.
    private func audioFiles(_ key: UUID) throws -> [String: Data] {
        let dir = env.cache.directory(for: key)
        guard let names = FileManager.default.subpaths(atPath: dir.path) else { return [:] }
        var out: [String: Data] = [:]
        for name in names {
            var isDir: ObjCBool = false
            let url = dir.appending(path: name)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out[name] = try Data(contentsOf: url)
        }
        return out
    }

    private func pendingWork() -> [LibraryAudioWork] {
        (try? env.context.fetch(FetchDescriptor<LibraryAudioWork>())) ?? []
    }

    /// The kept page has every paragraph's audio it can use, the merged copy's files are gone,
    /// its pending render is dropped and the crash-resume point names the kept page.
    private func assertMerged(_ rows: DuplicateRows, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(env.pages().map(\.key), [rows.kept], "one page, the further one", file: file, line: line)
        for (i, text) in rows.keptText.enumerated() {
            XCTAssertEqual(env.cache.entry(articleID: rows.kept, paragraphIndex: i)?.textHash,
                           ArticleIdentity.paragraphHash(text), "paragraph \(i)", file: file, line: line)
        }
        XCTAssertFalse(env.cache.hasCache(for: rows.merged), file: file, line: line)
        XCTAssertFalse(PendingBakeJobStore.shared.pendingJobs().contains { $0.articleID == rows.merged }, file: file, line: line)
        let resume = try XCTUnwrap(ListenResumePointStore.shared.load(), file: file, line: line)
        XCTAssertNotNil(library.page(matching: resume), "the resume point names a page that exists", file: file, line: line)
        XCTAssertEqual(resume.articleKey, rows.kept.uuidString, file: file, line: line)
        XCTAssertEqual(resume.paragraph, 1, file: file, line: line)
        XCTAssertTrue(pendingWork().isEmpty, "nothing left to do", file: file, line: line)
    }

    /// The copy's save fails after dedupe merged two copies: the audio, the pending render and
    /// the crash-resume point are as they were, and the next launch merges them properly.
    func testAFailedSaveLeavesAudioPendingRendersAndTheResumePointAlone() throws {
        let rows = try duplicateRows()
        let audioBefore = (try audioFiles(rows.merged), try audioFiles(rows.kept))
        let jobsBefore = PendingBakeJobStore.shared.pendingJobs()
        let resumeBefore = ListenResumePointStore.shared.load()
        library.saveContext = { _ in throw SaveFailed() }

        XCTAssertFalse(library.migrateLegacy().saved)
        XCTAssertEqual(try audioFiles(rows.merged), audioBefore.0, "the merged copy's audio is untouched")
        XCTAssertEqual(try audioFiles(rows.kept), audioBefore.1, "and so is the kept one's")
        XCTAssertEqual(PendingBakeJobStore.shared.pendingJobs(), jobsBefore, "the pending render is still there")
        XCTAssertEqual(ListenResumePointStore.shared.load(), resumeBefore, "the resume point is unchanged")

        try env.relaunch()
        XCTAssertTrue(library.migrateLegacy().saved)
        try assertMerged(rows)
    }

    /// The app dies right after the copy's save, before the audio work: the next launch finds
    /// the work in the store and does it.
    func testWorkLeftByALaunchThatDiedAfterItsSaveIsDoneNextLaunch() throws {
        let rows = try duplicateRows()
        let audioBefore = try audioFiles(rows.merged)
        // Saved, then gone before anything else ran.
        library.saveContext = { try $0.save(); throw SaveFailed() }
        library.migrateLegacy()
        XCTAssertEqual(try audioFiles(rows.merged), audioBefore, "the work hadn't run")

        try env.relaunch()
        XCTAssertEqual(env.pages().map(\.key), [rows.kept], "the merge itself was saved")
        XCTAssertEqual(pendingWork().count, 1, "with its audio work")
        XCTAssertEqual(library.finishAudioWork(), 1)
        try assertMerged(rows)
        XCTAssertEqual(library.migrateLegacy().copiedArticles, 0, "the copy was recorded")
    }

    /// The work ran but its records weren't deleted (the app died before that save): doing it
    /// again changes nothing, and the crash-resume point isn't moved a second time.
    func testWorkDoneTwiceMovesNothingTwice() throws {
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let old = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false)
        let new = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title)
        let iGiant = old.paragraphs.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let iAfter = iGiant + 1
        let key = UUID()
        let page = Page(key: key, title: title, byline: "example.com",
                        urlString: "https://example.com/classics/boscombe-valley", contentState: .saved, addedAt: env.now)
        page.cleanedHTML = html
        page.listenBlocksData = try JSONEncoder().encode(old.paragraphs)
        page.listenBlocksVersion = 2
        page.paragraphCount = old.count
        env.context.insert(page)
        try env.context.save()
        try env.storeAudio(key, paragraph: iAfter, text: old.paragraphs[iAfter])
        ListenResumePointStore.shared.save(article: key, paragraph: iAfter, at: date(1))

        var saves = 0
        library.saveContext = { context in
            saves += 1
            if saves == 2 { throw SaveFailed() } // the save that deletes the done work
            try context.save()
        }
        library.migrateParagraphLayout()
        let shifted = iAfter + 3
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, shifted)
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: shifted)?.textHash,
                       ArticleIdentity.paragraphHash(new.paragraphs[shifted]))
        let files = try audioFiles(key).keys.sorted()

        try env.relaunch()
        XCTAssertEqual(pendingWork().count, 1, "the done work's record survived")
        XCTAssertEqual(library.finishAudioWork(), 1)
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, shifted, "moved once")
        XCTAssertEqual(env.cache.entry(articleID: key, paragraphIndex: shifted)?.textHash,
                       ArticleIdentity.paragraphHash(new.paragraphs[shifted]))
        XCTAssertEqual(try audioFiles(key).keys.sorted(), files, "the audio is as the first run left it")
        XCTAssertTrue(pendingWork().isEmpty)
    }
}
