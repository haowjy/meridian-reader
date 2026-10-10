import XCTest
@testable import MeridianReader

/// Sources hand out pages and their normalized content the same way, whatever the pages are.
@MainActor
final class PageSourceTests: XCTestCase {
    func testTheBrowsersPageIsOnePageInNoFolder() async throws {
        let url = URL(string: "https://example.com/story?utm_source=x")!
        let source = SingleWebPageSource(url: url, pageTitle: "A Story", htmlSnapshot: "<html></html>",
                                         extractor: FakeArticleExtractor(mode: .success))
        XCTAssertNil(source.details)
        let pages = try await source.knownPages()
        XCTAssertEqual(pages, [PageRef(key: ArticleIdentity.articleKey(url: url), locator: .web(url), ordinal: 0, title: "A Story")])
        let next = try await source.page(after: pages[0])
        XCTAssertNil(next)

        let content = try await source.content(of: pages[0])
        let extracted = try await FakeArticleExtractor(mode: .success)
            .extract(from: ExtractionContext(origin: .web(url), pageTitle: "A Story", htmlSnapshot: "<html></html>"))
        XCTAssertEqual(content.extracted, extracted, "today's extraction, unchanged")
        XCTAssertEqual(content.document, ReaderArticle(id: UUID(), url: url, extracted: extracted).document,
                       "the listen blocks the Reader builds")

        let other = PageRef(key: UUID(), locator: .web(URL(string: "https://example.com/other")!), ordinal: 0)
        do {
            _ = try await source.content(of: other)
            XCTFail("not its page")
        } catch {
            XCTAssertEqual(error as? PageSourceError, .unknownPage)
        }
    }

    func testABookHandsOutItsSettledChaptersInOrder() async throws {
        let book = try BookImportTests.sampleBook().read(in: self)
        let source = try await EPUBSource.prepare(book, fallbackTitle: "file", normalizer: ListenContentNormalizer()) { _, _ in }
        let details = try XCTUnwrap(source.details)
        XCTAssertEqual(details.kind, .book)
        XCTAssertEqual(details.title, "The Lantern Keeper")
        XCTAssertEqual(details.sourceIdentifier, book.key.uuidString)

        let pages = try await source.knownPages()
        XCTAssertEqual(pages.map(\.key), book.chapters.map(\.key))
        XCTAssertEqual(pages.map(\.ordinal), Array(0..<pages.count))
        XCTAssertEqual(pages.map(\.skipsInPlayback), [true, false, false, false])
        var walked = [pages[0]]
        while let next = try await source.page(after: walked.last!) { walked.append(next) }
        XCTAssertEqual(walked, pages)

        let chapterOne = try await source.content(of: pages[1])
        XCTAssertEqual(chapterOne.title, "Chapter 1: The Harbor")
        XCTAssertEqual(chapterOne.languageCode, "en")
        XCTAssertEqual(chapterOne.document.paragraphs, source.chapters[1].document.paragraphs)
        XCTAssertEqual(chapterOne.plainText, chapterOne.document.paragraphs.joined(separator: "\n\n"))
        guard case .book(let locator) = chapterOne.ref.locator else { return XCTFail("a book locator") }
        XCTAssertEqual(locator.pageLocator, "OEBPS/one.xhtml#c1")
    }
}
