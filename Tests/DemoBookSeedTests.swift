import SwiftData
import XCTest
@testable import MeridianReader

/// `-seedDemoBook` runs on a phone with real data (the chapter-boundary device check): each
/// launch replaces what an earlier one seeded, and only that. A page of the user's at one of the
/// seed's addresses is never touched, by the seed or by the launch's dedupe after it.
@MainActor
final class DemoBookSeedTests: XCTestCase {
    private var env: LibraryTestEnvironment!

    override func setUp() async throws { env = try LibraryTestEnvironment() }

    override func tearDown() async throws { env.cleanUp() }

    /// A launch's seed, then the launch's dedupe, as `AppLaunch.maintainLibrary` runs them.
    private func launch() {
        LaunchHooks.seedDemoBook(in: env.library)
        env.library.dedupe()
    }

    private func demoBooks() -> [Folder] { env.folders().filter { $0.sourceIdentifier == DemoBook.sourceIdentifier } }

    private func pages(at url: URL) -> [Page] {
        let canonical = ArticleIdentity.canonicalURLString(from: url)
        return env.pages().filter { $0.canonicalURL == canonical }
    }

    /// A page of the user's at `url`, saved in no folder, with text and audio.
    private func usersPage(at url: URL, title: String) throws -> Page {
        let text = ["\(title): my own first paragraph.", "\(title): my own second paragraph."]
        let page = Page(key: UUID(), title: title, byline: "example.com", urlString: url.absoluteString,
                        contentState: .saved, addedAt: env.now, sortKey: env.library.nextSortKey(in: nil))
        page.plainText = text.joined(separator: "\n\n")
        page.storeListenParagraphs(text)
        env.context.insert(page)
        env.library.commit("user's page")
        try env.storeAudio(page.listenKey, paragraphs: text)
        return page
    }

    func testRepeatedLaunchesKeepOneDemoBookAndOneLoosePage() {
        launch()
        let firstBook = demoBooks().first
        launch()

        XCTAssertEqual(demoBooks().count, 1, "the earlier seed's book is replaced")
        XCTAssertFalse(demoBooks().first === firstBook)
        XCTAssertEqual(demoBooks().first.map { env.library.pages(in: $0).count }, DemoBook.chapters.count)
        let loose = pages(at: DemoBook.loosePageURL)
        XCTAssertEqual(loose.count, 1, "and its page in no folder")
        XCTAssertEqual(loose.first?.locator, DemoBook.loosePageMarker)
        XCTAssertNil(loose.first?.folder)
    }

    /// The user has pages at the address of the seed's page in no folder and of one of its
    /// chapters. Launch after launch, both stay as they were, with their audio, in no folder,
    /// and the only pages at those addresses; the seed adds no page in no folder, and that
    /// chapter goes without its address.
    func testRepeatedLaunchesLeaveTheUsersPagesAtTheSeedsAddresses() throws {
        let chapterURL = DemoBook.url(ofChapter: 1)
        let mine = try usersPage(at: DemoBook.loosePageURL, title: "Mine")
        let alsoMine = try usersPage(at: chapterURL, title: "Also Mine")
        let users = [(mine, DemoBook.loosePageURL, mine.listenKey, mine.plainText),
                     (alsoMine, chapterURL, alsoMine.listenKey, alsoMine.plainText)]

        for run in 1...3 {
            launch()
            for (page, url, key, text) in users {
                let present = !page.isDeleted && page.modelContext != nil
                XCTAssertTrue(present, "launch \(run): \(url) deleted")
                guard present else { continue }
                XCTAssertEqual(pages(at: url).map(\.key), [key], "launch \(run): the only page at \(url)")
                XCTAssertNil(page.folder, "launch \(run): still in no folder")
                XCTAssertNil(page.locator, "launch \(run)")
                XCTAssertEqual(page.plainText, text, "launch \(run): its own text")
                XCTAssertTrue(env.cache.hasCache(for: key), "launch \(run): its audio")
            }
            XCTAssertEqual(demoBooks().count, 1, "launch \(run)")
            let chapters = try XCTUnwrap(demoBooks().first.map { env.library.pages(in: $0) })
            XCTAssertEqual(chapters.count, DemoBook.chapters.count, "launch \(run): every chapter seeded")
            XCTAssertNil(chapters[1].urlString, "launch \(run): the chapter whose address is taken goes without it")
            XCTAssertEqual(chapters[2].urlString, DemoBook.url(ofChapter: 2).absoluteString)
            XCTAssertTrue(env.pages().allSatisfy { $0.locator != DemoBook.loosePageMarker }, "launch \(run)")
        }
    }

    /// Seeded chapters hold what an imported one does: their listen paragraphs and word count.
    func testSeededChaptersHoldTheirListenParagraphs() throws {
        launch()
        let chapters = try XCTUnwrap(demoBooks().first.map { env.library.pages(in: $0) })
        for chapter in chapters {
            XCTAssertFalse(chapter.cachedListenParagraphs?.isEmpty ?? true, chapter.title)
            XCTAssertEqual(chapter.paragraphCount, chapter.cachedListenParagraphs?.count, chapter.title)
            XCTAssertEqual(chapter.wordCount, WordCount.count(chapter.plainText), chapter.title)
        }
    }
}
