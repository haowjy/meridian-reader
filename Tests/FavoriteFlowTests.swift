import XCTest
@testable import MeridianReader

/// ☆ on a folder says what it did as a page's ☆ does, and says so when it can't be stored.
@MainActor
final class FavoriteFlowTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    func testAFolderStarSaysWhatItDid() throws {
        let shell = ShellState()
        let folder = try library.makeFolder(name: "Essays", in: nil)
        let flow = FavoriteFlow(library: library, shell: shell)

        flow.toggle(folder)
        XCTAssertTrue(folder.isFavorite)
        XCTAssertEqual(shell.toast?.message, "Added to Favorites")

        flow.toggle(folder)
        XCTAssertFalse(folder.isFavorite)
        XCTAssertEqual(shell.toast?.message, "Removed from Favorites")
    }

    private struct SaveFailed: Error {}

    func testAFolderStarThatCantBeStoredSaysSo() throws {
        let shell = ShellState()
        let folder = try library.makeFolder(name: "Essays", in: nil)
        library.saveContext = { _ in throw SaveFailed() }

        FavoriteFlow(library: library, shell: shell).toggle(folder)
        XCTAssertFalse(folder.isFavorite, "rolled back")
        XCTAssertEqual(shell.toast?.message, "Couldn’t add to Favorites")
    }
}
