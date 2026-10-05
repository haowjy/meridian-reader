import XCTest
@testable import Reader

/// Chapters settled on their listen blocks, before any key is kept: empty ones go, short body
/// chapters join a neighbour, front and back matter stay as they are.
final class BookChapterFinalizerTests: XCTestCase {
    private func chapter(_ name: String, words: Int, skips: Bool = false, title: String? = nil,
                         html: String? = nil) -> PreparedChapter {
        let body = html ?? (words == 0 ? "" : "<p>\(SyntheticEPUB.words(words, seed: name.count))</p>")
        return PreparedChapter(key: UUID(), title: title ?? name, locator: EPUBLocator(href: "\(name).xhtml", anchor: .fileStart),
                               skipsInPlayback: skips, html: body)
    }

    func testAChapterWithNothingToReadIsDropped() {
        let chapters = [chapter("cover", words: 0, skips: true), chapter("one", words: 500), chapter("pictures", words: 0)]
        let out = BookChapterFinalizer.finalize(chapters)
        XCTAssertEqual(out.map(\.key), [chapters[1].key])
    }

    func testAShortBodyChapterJoinsTheNextOneWhichKeepsItsKeyAndTitle() {
        let chapters = [chapter("one", words: 500), chapter("epigraph", words: 40), chapter("two", words: 500)]
        let out = BookChapterFinalizer.finalize(chapters)
        XCTAssertEqual(out.map(\.key), [chapters[0].key, chapters[2].key])
        XCTAssertEqual(out[1].title, "two")
        XCTAssertEqual(out[1].words, 540)
        XCTAssertEqual(out[1].document.paragraphs, chapters[1].document.paragraphs + chapters[2].document.paragraphs,
                       "its text first, in reading order")
    }

    func testTheLastShortBodyChapterJoinsTheOneBefore() {
        let chapters = [chapter("one", words: 500), chapter("coda", words: 30)]
        let out = BookChapterFinalizer.finalize(chapters)
        XCTAssertEqual(out.map(\.key), [chapters[0].key])
        XCTAssertEqual(out[0].document.paragraphs, chapters[0].document.paragraphs + chapters[1].document.paragraphs)
    }

    func testShortRunsGatherUntilTheyPassTheBar() {
        let chapters = (0..<5).map { chapter("part\($0)", words: 30) }
        let out = BookChapterFinalizer.finalize(chapters)
        XCTAssertEqual(out.count, 1, "five 30-word parts make one chapter")
        XCTAssertEqual(out[0].words, 150)
        XCTAssertEqual(out[0].key, chapters[3].key, "four gather forward, then the last joins them")
    }

    func testShortFrontAndBackMatterStay() {
        let chapters = [chapter("title", words: 8, skips: true), chapter("one", words: 500), chapter("colophon", words: 20, skips: true)]
        XCTAssertEqual(BookChapterFinalizer.finalize(chapters).map(\.key), chapters.map(\.key))
    }

    func testAShortBodyChapterBetweenSkippedOnesStays() {
        let chapters = [chapter("title", words: 8, skips: true), chapter("lonely", words: 60), chapter("notes", words: 900, skips: true)]
        XCTAssertEqual(BookChapterFinalizer.finalize(chapters).map(\.key), chapters.map(\.key), "no body neighbour to join")
    }

    func testAMergeNeverPassesTheMaximum() {
        let bar = BookChapterFinalizer.Bar(minWords: 100, maxWords: 1_000)
        let chapters = [chapter("one", words: 960), chapter("short", words: 60), chapter("two", words: 990)]
        XCTAssertEqual(BookChapterFinalizer.finalize(chapters, bar: bar).map(\.key), chapters.map(\.key))
        XCTAssertNil(BookChapterFinalizer.overCap(chapters, bar: bar))
        XCTAssertEqual(BookChapterFinalizer.overCap([chapter("long", words: 1_200)], bar: bar), 1_200)
        XCTAssertNil(BookChapterFinalizer.overCap([chapter("long notes", words: 1_200, skips: true)], bar: bar),
                     "skipped matter has no bar")
    }

    func testABookWithOnlySkippedChaptersPlaysThemAll() {
        let chapters = [chapter("a", words: 300, skips: true), chapter("b", words: 300, skips: true)]
        XCTAssertEqual(BookChapterFinalizer.finalize(chapters).map(\.skipsInPlayback), [false, false])
    }

    func testAnUntitledChapterIsNamedByItsFirstWords() {
        let long = PreparedChapter(key: UUID(), title: nil, locator: EPUBLocator(href: "p.xhtml", anchor: .fileStart),
                                   skipsInPlayback: false,
                                   html: "<p>To the reader who opens this page there is a long sentence here.</p><p>More.</p>")
        XCTAssertEqual(long.title, "To the reader who opens this page there…")
        let heading = PreparedChapter(key: UUID(), title: nil, locator: EPUBLocator(href: "p.xhtml", anchor: .fileStart),
                                      skipsInPlayback: false, html: "<h1>A Preface</h1><p>Some words follow it.</p>")
        XCTAssertEqual(heading.title, "A Preface")
        XCTAssertEqual(heading.document.paragraphs, ["Some words follow it."],
                       "the heading that names it isn't read twice, as for any title")
    }

    func testListenBlocksAreBuiltAsTheLibraryBuildsThem() {
        let c = chapter("one", words: 0, title: "Chapter One", html: "<h1>Chapter One</h1><p>Text.</p><p>More text.</p>")
        XCTAssertEqual(c.document, Page.buildListenDocument(plainText: "", cleanedHTML: c.html, title: c.title))
        XCTAssertEqual(c.document.paragraphs, ["Text.", "More text."])
    }
}
