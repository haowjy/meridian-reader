import XCTest
@testable import Reader

/// Book and chapter keys: the same file gives the same keys on every import (they're audio cache
/// keys), chapters cut from one file differ by fragment, and the inputs are pinned.
final class BookIdentityTests: XCTestCase {
    private let identifier = "urn:uuid:5a1b2c3d-1111-4222-8333-944455556666"

    private func book() -> SyntheticEPUB {
        var epub = SyntheticEPUB()
        epub.addDocument("one.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c1", heading: "Chapter 1", words: 600)
            + SyntheticEPUB.chapter(id: "c2", heading: "Chapter 2", words: 600, seed: 1)))
        epub.addDocument("two.xhtml", body: SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 600, seed: 2)))
        epub.contents = [.init("Chapter 1", "one.xhtml#c1"), .init("Chapter 2", "one.xhtml#c2"), .init("Chapter 3", "two.xhtml")]
        return epub
    }

    func testKeysAreStableAcrossReimport() throws {
        let epub = book()
        let first = try epub.read(in: self)
        let again = try epub.read(in: self)
        XCTAssertEqual(first.key, again.key)
        XCTAssertEqual(first.chapters.map(\.key), again.chapters.map(\.key))
        XCTAssertEqual(first.fileFingerprint, again.fileFingerprint)
        XCTAssertEqual(Set(first.chapters.map(\.key)).count, 3, "chapters cut from one file have distinct keys")
    }

    func testKeysArePinned() {
        let bookKey = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "unused")
        XCTAssertEqual(bookKey, UUID(uuidString: "91E71841-A9BC-39D1-5CBD-9F198D3E2B77"))
        XCTAssertEqual(BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", fragment: "c1")),
                       UUID(uuidString: "2E057AB6-DEAC-9EB1-87CF-7FFC285454AE"))
        XCTAssertEqual(BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", fragment: nil)),
                       UUID(uuidString: "9A9C0D0D-84F3-AD44-0D22-2019A4F58B79"))
        XCTAssertEqual(BookIdentity.bookKey(identifier: nil, title: "Anything", fileFingerprint: "abc123"),
                       UUID(uuidString: "4F75D552-9F5F-C43B-F902-B5B184EE865A"))
    }

    func testChapterKeysDifferByFragmentAndByBook() {
        let bookKey = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "")
        let otherBook = BookIdentity.bookKey(identifier: "urn:example:other", title: "The Synthetic Book", fileFingerprint: "")
        let keys = [
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", fragment: nil)),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", fragment: "c1")),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/one.xhtml", fragment: "c2")),
            BookIdentity.chapterKey(bookKey: bookKey, locator: EPUBLocator(href: "OEBPS/two.xhtml", fragment: "c1")),
            BookIdentity.chapterKey(bookKey: otherBook, locator: EPUBLocator(href: "OEBPS/one.xhtml", fragment: "c1")),
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertNotEqual(keys[1], ArticleIdentity.articleKey(canonicalURL: "OEBPS/one.xhtml"),
                          "a chapter key never collides with a web article key")
    }

    func testTitleSeparatesEditionsSharingAnIdentifier() {
        let epub3 = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "a")
        let illustrated = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book, Illustrated", fileFingerprint: "b")
        XCTAssertNotEqual(epub3, illustrated)
        XCTAssertEqual(BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "b"), epub3,
                       "with a real identifier, the file's bytes don't matter")
    }

    func testWhitespaceDoesNotChangeTheKey() {
        let plain = BookIdentity.bookKey(identifier: identifier, title: "The Synthetic Book", fileFingerprint: "")
        XCTAssertEqual(BookIdentity.bookKey(identifier: "  \(identifier)\n", title: "The  Synthetic\nBook ", fileFingerprint: ""), plain)
    }

    func testPlaceholderIdentifierFallsBackToTheFile() throws {
        for placeholder in [nil, "", "  ", "urn:uuid:00000000-0000-0000-0000-000000000000", "00000000-0000-0000-0000-000000000000"] {
            XCTAssertNil(BookIdentity.usableIdentifier(placeholder), placeholder ?? "nil")
        }
        XCTAssertEqual(BookIdentity.usableIdentifier(" urn:isbn:9990000000017 "), "urn:isbn:9990000000017")

        var first = book()
        first.identifier = "urn:uuid:00000000-0000-0000-0000-000000000000"
        var second = first
        second.documents[1].body = SyntheticEPUB.xhtml(body: SyntheticEPUB.chapter(id: "c3", heading: "Chapter 3", words: 700, seed: 9))
        let a = try first.read(in: self)
        let b = try second.read(in: self)
        XCTAssertNotEqual(a.key, b.key, "two different files sharing a placeholder identifier and title stay apart")
        XCTAssertEqual(a.key, BookIdentity.bookKey(identifier: nil, title: nil, fileFingerprint: a.fileFingerprint))
        XCTAssertEqual(try first.read(in: self).key, a.key, "the same file still gets the same key")
    }

    func testFileFingerprintIsTheFilesSHA256() throws {
        let url = try SyntheticEPUB.write(Data("abc".utf8), in: self)
        XCTAssertEqual(try BookIdentity.fileFingerprint(of: url),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
