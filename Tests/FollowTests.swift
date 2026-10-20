import XCTest
@testable import MeridianReader

/// Follow's pure rules: reading a story's chapters off its table of contents (Royal Road's rule,
/// the generic one), the fetch queue's pace and back-off and the notice it shows, and which pages
/// join a folder's download while its switch is on.
final class FollowTests: XCTestCase {
    private func link(_ url: String, _ text: String, list: Int) -> LinkPage.Link {
        LinkPage.Link(url: URL(string: url)!, text: text, list: list)
    }

    // MARK: - Royal Road

    /// Royal Road: the chapters table wins over the *Start Reading* button and each row's date
    /// link: one chapter per address, named by its row's first link, in the story's order; links
    /// to other stories and the site's menus are left out. The title loses the site's name.
    func testContentsReaders() throws {
        let story = "https://www.royalroad.com/fiction/40512/the-copper-orchard"
        let article = LinkPage(url: URL(string: story)!, title: "The Copper Orchard | Royal Road", heading: nil,
                            author: " orchard_writer ", links: [
            link("https://www.royalroad.com/fictions/best-rated", "Best Rated", list: 0),
            link("\(story)/chapter/900001/1-first-frost", "Start Reading", list: 1),
            link("\(story)/chapter/900001/1-first-frost", "1. First Frost", list: 2),
            link("\(story)/chapter/900001/1-first-frost", "8 years ago", list: 2),
            link("\(story)/chapter/900002/authors-note", "Author's Note: Hiatus", list: 2),
            link("\(story)/chapter/900002/authors-note", "7 years ago", list: 2),
            link("\(story)/chapter/900003/2-pruning-season", "2. Pruning Season", list: 2),
            link("\(story)/chapter/900003/2-pruning-season", "8 years ago", list: 2),
            link("https://www.royalroad.com/fiction/99999/other/chapter/1/one", "Another story", list: 3),
        ])
        let contents = try XCTUnwrap(TableOfContents.read(article))
        XCTAssertEqual(contents.title, "The Copper Orchard")
        XCTAssertEqual(contents.byline, "orchard_writer")
        XCTAssertEqual(contents.chapters.map(\.title), ["1. First Frost", "Author's Note: Hiatus", "2. Pruning Season"])

        // A chapter's address leads to its story's page; the site goes by its reader's name, or
        // by its host.
        let chapter = URL(string: "https://www.royalroad.com/fiction/40512/the-copper-orchard/chapter/900001/1-first?x=1")!
        XCTAssertEqual(TableOfContents.contentsURL(for: chapter).absoluteString, "https://www.royalroad.com/fiction/40512")
        XCTAssertEqual(TableOfContents.siteName(of: chapter), "Royal Road")
        let other = URL(string: "https://www.serials.example.com/story/contents")!
        XCTAssertEqual(TableOfContents.contentsURL(for: other), other)
        XCTAssertEqual(TableOfContents.siteName(of: other), "serials.example.com")

        // Any other site: the list with the most chapter-like links on the page's own site wins
        // over a longer menu; a link back to the page itself and other sites' links are left out.
        let site = "https://serials.example.com"
        let menu = ["Home", "Rankings", "Forums", "Sign In", "About", "Contact", "Help"].map {
            link("\(site)/\($0.lowercased())", $0, list: 0)
        }
        let tideKeeper = LinkPage(url: URL(string: "\(site)/tide-keeper")!, title: "The Tide Keeper", heading: "The Tide Keeper",
                            author: nil, links: menu + [
            link("\(site)/tide-keeper", "The Tide Keeper", list: 1),
            link("\(site)/tide-keeper/1", "Chapter 1: The Lamp", list: 1),
            link("\(site)/tide-keeper/note", "Author's Note", list: 1),
            link("\(site)/tide-keeper/2", "Chapter 2: Low Water", list: 1),
            link("https://elsewhere.example.org/ad", "Chapter 9 of something else", list: 1),
        ])
        let generic = try XCTUnwrap(TableOfContents.read(tideKeeper))
        XCTAssertEqual(generic.chapters.map(\.title), ["Chapter 1: The Lamp", "Author's Note", "Chapter 2: Low Water"])
        XCTAssertNil(TableOfContents.read(LinkPage(url: URL(string: site)!, title: nil, heading: nil, author: nil, links: menu)),
                     "a menu alone is no story")
    }

    // MARK: - Pace and back-off

    /// The pause is 4 s, 12 s after a slow reply; a refusal or no answer doubles the wait from a
    /// minute up to 30 minutes (never under a refusal's Retry-After); answers halve it back down.
    /// The header's notice names the chapter waiting by its title (as the next chapter when it
    /// has none), as a sentence.
    @MainActor
    func testPacingBacksOffAndItsNotice() {
        var pacing = FetchPacing()
        XCTAssertEqual(pacing.delay, 4)
        pacing.record(.answered(seconds: 1))
        XCTAssertEqual(pacing.delay, 4)
        pacing.record(.answered(seconds: 8))
        XCTAssertEqual(pacing.delay, 12, "slow reply")
        pacing.record(.refused(retryAfter: nil))
        XCTAssertEqual(pacing.delay, 60)
        XCTAssertTrue(pacing.isBackingOff)
        pacing.record(.noAnswer)
        XCTAssertEqual(pacing.delay, 120)
        pacing.record(.refused(retryAfter: 600))
        XCTAssertEqual(pacing.delay, 600, "the site's Retry-After")
        for _ in 0..<5 { pacing.record(.refused(retryAfter: nil)) }
        XCTAssertEqual(pacing.delay, 30 * 60, "capped")
        pacing.record(.answered(seconds: 1))
        XCTAssertEqual(pacing.delay, 15 * 60, "then slower")
        XCTAssertFalse(pacing.isBackingOff)
        for _ in 0..<12 { pacing.record(.answered(seconds: 1)) }
        XCTAssertEqual(pacing.delay, 4, "back to its pace")
        pacing.record(.refused(retryAfter: 3600))
        XCTAssertEqual(pacing.delay, 3600, "a site's Retry-After past the cap")

        // Retry-After as seconds or as an HTTP date.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(FetchPacing.retryAfter("120", now: now), 120)
        XCTAssertEqual(FetchPacing.retryAfter("Fri, 15 Jan 2027 08:00:30 GMT", now: now), 30)
        XCTAssertNil(FetchPacing.retryAfter("soon", now: now))

        XCTAssertEqual(FollowText.backOffNotice(site: "story", status: nil, chapter: .init(number: 6, title: "Chapter 6: The Wreck"),
                                                wait: 112),
                       "Story isn’t answering. “Chapter 6: The Wreck” is tried again in 1:52.")
        XCTAssertEqual(FollowText.backOffNotice(site: "story", status: 429, chapter: .init(number: 6, title: nil), wait: 112),
                       "Story asked to slow down (429). The next chapter in 1:52, then slower.", "a chapter without a title")
    }

    // MARK: - The Download switch

    /// A list written before the switch reads with every folder's switch on and nothing deleted;
    /// while on, a folder's new pages join it, its deleted ones don't; off, none do.
    func testDownloadListBeforeTheSwitchAndArticlesJoining() throws {
        let key = UUID(), other = UUID(), new = UUID()
        let old = """
        [{"id":"\(UUID())","target":{"folder":{"_0":"\(UUID())"}},"title":"Story","addedAt":0,"isPaused":false,
          "entries":[{"key":"\(key)","state":"done"}]}]
        """
        var record = try XCTUnwrap(JSONDecoder().decode([DownloadRecord].self, from: Data(old.utf8)).first)
        XCTAssertTrue(record.followsFolder)
        XCTAssertEqual(record.deleted, [])
        record.deleted = [other]
        XCTAssertEqual(record.joining([key, other, new]), [new])
        record.followsFolder = false
        XCTAssertEqual(record.joining([key, other, new]), [])
    }
}
