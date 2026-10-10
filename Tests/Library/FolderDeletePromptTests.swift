import XCTest
@testable import MeridianReader

/// The question deleting folders asks: *Delete Folder Only* only when nothing selected is a book
/// or series (books always go with their chapters), and the books named in every choice and in
/// the message when they are part of it.
@MainActor
final class FolderDeletePromptTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func fixed(_ name: String, _ kind: FolderKind) throws -> Folder {
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

    func testPlainFoldersOfferFolderOnly() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: shelf)
        let one = prompt([shelf])
        XCTAssertEqual(one.title, "Delete the folder “Shelf”?")
        XCTAssertEqual(one.message, "It holds 1 page. Delete Folder Only moves them up one level.")
        XCTAssertEqual(one.choices.map(\.id), ["deleteFolderOnly", "deleteFolderAndContents"])
        XCTAssertEqual(one.choices.map(\.keepsContents), [true, false])
        XCTAssertFalse(one.choices[0].isDestructive)

        let other = try library.makeFolder(name: "Other", in: nil)
        XCTAssertEqual(prompt([shelf, other]).choices.map(\.title), ["Delete Folders Only", "Delete Folders and Contents"])
    }

    /// A folder and a book: no *Folder Only*; both choices name the book, both are destructive,
    /// and the message says the book goes either way.
    func testAFolderAndABookNeverOfferFolderOnly() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: shelf)
        let book = try fixed("Novel", .book)
        let mixed = prompt([shelf, book], playing: true)
        XCTAssertEqual(mixed.title, "Delete 1 folder and the book?")
        XCTAssertFalse(mixed.choices.contains { $0.id == "deleteFolderOnly" || $0.title.contains("Only") })
        XCTAssertEqual(mixed.choices.map(\.title), ["Delete Book, Keep Folder Contents", "Delete Everything"])
        XCTAssertTrue(mixed.choices.allSatisfy(\.isDestructive))
        XCTAssertEqual(mixed.message, "“Novel” is deleted with its chapters and downloads either way. The folder holds 1 page. Stops what's playing.")
    }

    /// Several books (or a book and a series): one choice, deleting them whole.
    func testSeveralBooksOfferOnlyDeletingThemWhole() throws {
        let books = try prompt([fixed("One", .book), fixed("Two", .book)])
        XCTAssertEqual(books.title, "Delete 2 books?")
        XCTAssertEqual(books.choices.map(\.title), ["Delete 2 Books"])
        XCTAssertEqual(books.choices.map(\.keepsContents), [false])
        XCTAssertEqual(books.message, "Their chapters and downloads are deleted.")

        let mixedKinds = try prompt([fixed("Three", .book), fixed("Serial", .series), library.makeFolder(name: "Shelf", in: nil)])
        XCTAssertEqual(mixedKinds.title, "Delete 1 folder and 1 book and 1 series?")
        XCTAssertEqual(mixedKinds.choices.first?.title, "Delete 1 Book and 1 Series, Keep Folder Contents")

        XCTAssertEqual(try prompt([fixed("Single", .series)]).choices.map(\.title), ["Delete Series"])
    }

    /// "Stops what's playing." is said of the choices that delete the page playing: *Delete
    /// Folder Only* keeps a plain folder's pages, and keeping contents beside a book deletes only
    /// the book. A chapter of the book playing is stopped by every choice.
    func testOnlyTheChoicesThatDeleteThePagePlayingSayTheyStopIt() throws {
        let shelf = try library.makeFolder(name: "Shelf", in: nil)
        let page = try library.addLink(url: URL(string: "https://example.com/a")!, title: "A", artwork: nil, in: shelf)
        XCTAssertEqual(prompt([shelf], playing: page.listenKey).message,
                       "It holds 1 page. Delete Folder Only moves them up one level. Delete Folder and Contents stops what's playing.")

        let book = try fixed("Novel", .book)
        let chapter = try XCTUnwrap(library.pages(in: book).first)
        XCTAssertEqual(prompt([shelf, book], playing: page.listenKey).message,
                       "“Novel” is deleted with its chapters and downloads either way. The folder holds 1 page. Delete Everything stops what's playing.")
        XCTAssertEqual(prompt([shelf, book], playing: chapter.listenKey).message,
                       "“Novel” is deleted with its chapters and downloads either way. The folder holds 1 page. Stops what's playing.")
        XCTAssertEqual(prompt([book], playing: chapter.listenKey).message, "Its chapters and their downloads are deleted. Stops what's playing.")
        XCTAssertEqual(prompt([shelf, book], playing: UUID()).message,
                       "“Novel” is deleted with its chapters and downloads either way. The folder holds 1 page.")
    }
}
