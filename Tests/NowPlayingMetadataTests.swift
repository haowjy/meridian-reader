import MediaPlayer
import UIKit
import XCTest
@testable import MeridianReader

/// What the lock screen shows: for a chapter, its title, the book's byline with the paragraph,
/// the book as the album and the book's cover when the chapter has no artwork; for a page in no
/// book, its site.
@MainActor
final class NowPlayingMetadataTests: XCTestCase {
    private var fixture: TestSpeech!
    private var speech: SpeechController { fixture.speech }

    override func setUp() async throws { fixture = TestSpeech() }
    override func tearDown() async throws { fixture.tearDown() }

    private static let cover = UIImage(systemName: "book")!.pngData()!

    func testAChapterShowsItsTitleTheBooksBylineAndTheBook() throws {
        let session = SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["One.", "Two.", "Three."]),
                                    detectedLanguage: "en", title: "Chapter 12: Hunsford", site: "Jane Austen",
                                    artwork: Self.cover, folder: PlaybackFolder(id: UUID(), name: "Pride and Prejudice", isBookOrSeries: true))
        speech.start(session, at: ListenSpot(paragraph: 1))
        let info = try XCTUnwrap(speech.lockScreen.lastInfo)
        XCTAssertEqual(info.title, "Chapter 12: Hunsford")
        XCTAssertEqual(info.subtitle, "Jane Austen – Paragraph 2 of 3")
        XCTAssertEqual(info.albumTitle, "Pride and Prejudice")
        XCTAssertEqual(info.artwork, Self.cover)

        let fields = speech.lockScreen.fields(for: info)
        XCTAssertEqual(fields[MPMediaItemPropertyTitle] as? String, "Chapter 12: Hunsford")
        XCTAssertEqual(fields[MPMediaItemPropertyArtist] as? String, "Jane Austen – Paragraph 2 of 3")
        XCTAssertEqual(fields[MPMediaItemPropertyAlbumTitle] as? String, "Pride and Prejudice")
        let artwork = try XCTUnwrap(fields[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)

        speech.skipToNextParagraph()
        let next = try XCTUnwrap(speech.lockScreen.lastInfo)
        XCTAssertEqual(next.subtitle, "Jane Austen – Paragraph 3 of 3")
        XCTAssertTrue(speech.lockScreen.fields(for: next)[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork === artwork,
                      "the artwork is made once per picture, not per paragraph")
    }

    /// The lock screen and the bar show the same title, so a page without one reads "Untitled" on
    /// both.
    func testAPageWithoutATitleReadsTheSameOnTheLockScreenAndTheBar() throws {
        speech.start(SpeechSession(id: UUID(), document: ParagraphDocument(parts: ["One.", "Two."])))
        XCTAssertEqual(speech.nowPlaying?.title, "Untitled")
        XCTAssertEqual(try XCTUnwrap(speech.lockScreen.lastInfo).title, "Untitled")
    }

    func testAPageInNoBookShowsItsSite() throws {
        speech.listen(to: TestSpeech.article("https://example.com/a", title: "An Article"))
        let info = try XCTUnwrap(speech.lockScreen.lastInfo)
        XCTAssertEqual(info.title, "An Article")
        XCTAssertEqual(info.subtitle, "example.com – Paragraph 1 of 3")
        XCTAssertEqual(info.albumTitle, "example.com")
        XCTAssertEqual(info.dictionary[MPMediaItemPropertyAlbumTitle] as? String, "example.com")
    }

    /// A chapter from the library: the book's byline, and its cover when the chapter has no
    /// artwork of its own.
    func testALibraryChapterUsesTheBooksBylineAndCover() throws {
        let env = try LibraryTestEnvironment()
        defer { env.cleanUp() }
        let (book, pages) = ChapterAdvanceTests.seedBook(in: env.library, titles: ["Chapter 1", "Chapter 2"])
        book.byline = "Book Author"
        book.coverData = Self.cover
        pages[1].byline = "chapter byline"

        speech.start(.page(pages[1]))
        let info = try XCTUnwrap(speech.lockScreen.lastInfo)
        XCTAssertEqual(info.title, "Chapter 2")
        XCTAssertEqual(info.subtitle, "Book Author – Paragraph 1 of 3")
        XCTAssertEqual(info.albumTitle, "The Book")
        XCTAssertEqual(info.artwork, Self.cover, "the book's cover")
        XCTAssertEqual(speech.nowPlaying?.source, "The Book")

        let own = UIImage(systemName: "star")!.pngData()!
        pages[0].artworkData = own
        speech.start(.page(pages[0]))
        XCTAssertEqual(speech.lockScreen.lastInfo?.artwork, own, "a chapter's own artwork first")
    }
}
