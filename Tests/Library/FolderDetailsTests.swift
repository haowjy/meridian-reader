import SwiftData
import UIKit
import XCTest
@testable import MeridianReader

/// *Edit Details* (`LibraryStore.setDetails`): name, byline and cover in one edit; blanks keep
/// the name and clear the byline; the kind never changes, so a plain folder with details keeps a
/// folder's order, sort and drops. Favorites has none. A failed save leaves the details as they
/// were.
@MainActor
final class FolderDetailsTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment(fileBacked: true) }
    override func tearDown() async throws { env.cleanUp() }

    private let cover = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])

    private func savedPage(_ path: String, in folder: Folder?) throws -> Page {
        try library.save(env.article("https://example.com/\(path)", title: path), placement: .folder(folder))
    }

    func testDetailsSetNameBylineAndCoverAndKeepThePlainKind() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        XCTAssertFalse(folder.hasDetails)

        try library.setDetails(of: folder, name: "  Tide Tables ", byline: " A. Writer ", cover: cover)

        XCTAssertEqual(folder.name, "Tide Tables")
        XCTAssertEqual(folder.byline, "A. Writer")
        XCTAssertEqual(folder.coverData, cover)
        XCTAssertEqual(folder.kind, .plain, "details never make a folder a book")
        XCTAssertTrue(folder.hasDetails)

        let id = folder.id
        try env.relaunch()
        let stored = try XCTUnwrap(library.folder(id: id))
        XCTAssertEqual(stored.name, "Tide Tables")
        XCTAssertEqual(stored.byline, "A. Writer")
        XCTAssertEqual(stored.coverData, cover)
        XCTAssertEqual(stored.kind, .plain)
    }

    func testABlankNameKeepsTheNameAndABlankBylineClearsIt() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        try library.setDetails(of: folder, name: "Finance", byline: "A. Writer", cover: nil)
        XCTAssertTrue(folder.hasDetails, "a byline alone is details")

        try library.setDetails(of: folder, name: "   ", byline: "  ", cover: nil)
        XCTAssertEqual(folder.name, "Finance")
        XCTAssertNil(folder.byline)
        XCTAssertFalse(folder.hasDetails, "cleared: a plain folder's look again")
    }

    func testRemovingTheCoverClearsItAndKeepsTheByline() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        try library.setDetails(of: folder, name: "Finance", byline: nil, cover: cover)
        XCTAssertTrue(folder.hasDetails, "a cover alone is details")

        try library.setDetails(of: folder, name: "Finance", byline: "A. Writer", cover: nil)
        XCTAssertNil(folder.coverData)
        XCTAssertEqual(folder.byline, "A. Writer")
    }

    /// A folder with details is still a plain folder: pages move in and out, it takes drops, its
    /// sort is its own, and subfolders go inside.
    func testAFolderWithDetailsKeepsAFoldersRules() throws {
        let folder = try library.makeFolder(name: "Finance", in: nil)
        try library.setDetails(of: folder, name: "Finance", byline: "A. Writer", cover: cover)
        let loose = try savedPage("loose", in: nil)

        XCTAssertNil(library.moveRefusal(.page(loose), to: folder), "it takes a drop")
        try library.move([.page(loose)], to: folder)
        XCTAssertIdentical(loose.folder, folder)
        try library.setSort(.title, for: folder)
        XCTAssertEqual(folder.pageSort, .title, "its sort is its own, not a book's fixed order")
        let inside = try library.makeFolder(name: "Inside", in: folder)
        XCTAssertIdentical(inside.parent, folder)
        try library.move([.page(loose)], to: nil)
        XCTAssertNil(loose.folder, "pages move out")
        XCTAssertEqual(folder.kind, .plain)
    }

    func testABookKeepsItsKindAndItsSourceDetails() throws {
        let book = Folder(name: "Book", kind: .book)
        book.sourceIdentifier = "book-key"
        env.context.insert(book)
        try env.context.save()

        try library.setDetails(of: book, name: "Renamed Book", byline: "B. Author", cover: cover)
        XCTAssertEqual(book.kind, .book)
        XCTAssertEqual(book.name, "Renamed Book")
        XCTAssertEqual(book.byline, "B. Author")
        XCTAssertEqual(book.sourceIdentifier, "book-key", "what dedupe and Replace find it by stays")
    }

    func testFavoritesHasNoDetails() throws {
        let favorites = library.favorites()
        XCTAssertThrowsError(try library.setDetails(of: favorites, name: "Mine", byline: "A. Writer", cover: cover)) {
            XCTAssertEqual($0 as? LibraryTreeError, .favoritesIsPinned)
        }
        XCTAssertNil(favorites.byline)
        XCTAssertNil(favorites.coverData)
    }

    func testAFailedSaveLeavesTheDetailsAsTheyWere() throws {
        struct SaveFailed: Error {}
        let folder = try library.makeFolder(name: "Finance", in: nil)
        try library.setDetails(of: folder, name: "Finance", byline: "A. Writer", cover: nil)
        library.saveContext = { _ in throw SaveFailed() }

        XCTAssertThrowsError(try library.setDetails(of: folder, name: "Other", byline: nil, cover: cover)) {
            XCTAssertEqual($0 as? LibraryStoreError, .saveFailed)
        }
        XCTAssertEqual(folder.name, "Finance")
        XCTAssertEqual(folder.byline, "A. Writer")
        XCTAssertNil(folder.coverData)
    }

    /// A picked picture is kept as a cover thumbnail, as a book's cover is on import: its longer
    /// side at most 600 px, as JPEG.
    func testAPickedPictureIsMadeSmall() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 3000), format: format).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 3000))
        }
        let thumbnail = try XCTUnwrap(CoverThumbnail.make(from: big))
        let image = try XCTUnwrap(UIImage(data: thumbnail))
        XCTAssertEqual(max(image.size.width * image.scale, image.size.height * image.scale), 600, accuracy: 1)
        XCTAssertEqual(thumbnail.prefix(2), Data([0xFF, 0xD8]), "JPEG")
        XCTAssertNil(CoverThumbnail.make(from: Data("not a picture".utf8)), "a file that isn't a picture is refused")
    }
}
