import XCTest
@testable import MeridianReader

/// The question deleting folders asks: one destructive choice that deletes everything selected
/// with its contents (no keep-contents choice), plus Cancel; books and series asked about as any
/// folder.
@MainActor
final class FolderDeletePromptTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func book(_ name: String, _ kind: FolderKind = .book) throws -> Folder {
        let folder = Folder(name: name, kind: kind)
        env.context.insert(folder)
        try library.addLink(url: URL(string: "https://example.com/\(name.lowercased())/ch1")!, title: "Ch 1", artwork: nil, in: folder)
        return folder
    }

    private func prompt(_ folders: [Folder], playing: Bool = false) -> FolderDeletePrompt {
        FolderDeletePrompt(folders: folders, contents: library.contents(of:)) { _ in playing }
    }

    /// The prompt while the page keyed `playing` is what you hear.
    private func prompt(_ folders: [Folder], playing key: UUID?) -> FolderDeletePrompt {
        FolderDeletePrompt(folders: folders, contents: library.contents(of:)) { keys in key.map(keys.contains) ?? false }
    }

    /// Plain folders: one destructive choice, deleting the folder and what it holds.
    func testPlainFoldersOfferOnlyDeletingWithContents() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: shelf)
        let one = prompt([shelf])
        XCTAssertEqual(one.title, "Delete the folder “Shelf”?")
        XCTAssertEqual(one.message, "It holds 1 page. They're deleted too.")
        XCTAssertEqual(one.choices.map(\.id), ["deleteFolderAndContents"])
        XCTAssertTrue(one.choices[0].isDestructive)

        let other = try library.makeFolder(name: "Other", in: nil)
        XCTAssertEqual(prompt([shelf, other]).choices.map(\.title), ["Delete Folders and Contents"])
    }

    /// A book or series is asked about as any folder (decision D19): its chapters count as pages,
    /// and it counts as a folder inside another.
    func testABookIsAskedAboutAsAFolder() throws {
        let novel = try book("Novel")
        let one = prompt([novel])
        XCTAssertEqual(one.title, "Delete the folder “Novel”?")
        XCTAssertEqual(one.message, "It holds 1 page. They're deleted too.")
        XCTAssertEqual(one.choices.map(\.title), ["Delete Folder and Contents"])

        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: shelf)
        try library.move([.folder(book("Serial", .series))], to: shelf)
        let mixed = prompt([shelf, novel])
        XCTAssertEqual(mixed.title, "Delete 2 folders?")
        XCTAssertEqual(mixed.message, "They hold 1 folder, 3 pages. They're deleted too.")
        XCTAssertEqual(mixed.choices.map(\.id), ["deleteFolderAndContents"])
        XCTAssertEqual(mixed.choices.map(\.title), ["Delete Folders and Contents"])
    }

    /// "Stops what's playing." when the page playing is anywhere in what's deleted.
    func testItSaysItStopsThePagePlayingOnlyWhenDeletingIt() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let page = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: shelf)
        XCTAssertEqual(prompt([shelf], playing: page.listenKey).message, "It holds 1 page. They're deleted too. Stops what's playing.")

        let novel = try book("Novel")
        let chapter = try XCTUnwrap(library.pages(in: novel).first)
        XCTAssertEqual(prompt([shelf, novel], playing: chapter.listenKey).message,
                       "They hold 2 pages. They're deleted too. Stops what's playing.")
        XCTAssertEqual(prompt([shelf, novel], playing: UUID()).message, "They hold 2 pages. They're deleted too.")
    }
}
