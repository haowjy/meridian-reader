import XCTest
@testable import MeridianReader

/// The Library home's tab (Everything or Favorites) belongs to `ShellState`: going to a place in
/// the Library shows Everything, where every place is listed; ⋯ → Favorites shows Favorites; 📚
/// keeps the tab you left. It is remembered with the surface.
@MainActor
final class LibraryTabTests: XCTestCase {
    private var store: SurfaceMemoryStore!

    override func setUp() {
        store = SurfaceMemoryStore(defaults: UserDefaults(suiteName: "LibraryTabTests-\(UUID())")!)
    }

    func testFavoritesOpensTheHomeOnFavorites() {
        let shell = ShellState()
        shell.showLibrary(at: [.folder(UUID())])
        shell.showFavorites()
        XCTAssertTrue(shell.isInLibrary)
        XCTAssertEqual(shell.libraryPath, [], "the home")
        XCTAssertTrue(shell.favoritesOnly)
    }

    func testGoingToAPlaceShowsEverything() {
        let shell = ShellState()
        shell.showFavorites()
        shell.showLibrary(at: [])
        XCTAssertFalse(shell.favoritesOnly, "Go to Library: the home, on Everything")

        shell.showFavorites()
        let folder = UUID()
        shell.showLibrary(at: [.folder(folder)])
        XCTAssertEqual(shell.libraryPath, [.folder(folder)])
        XCTAssertFalse(shell.favoritesOnly, "Go to a folder: back from it lands on Everything")
    }

    func testTheSwapKeepsTheTab() {
        let shell = ShellState()
        shell.showFavorites()
        shell.leaveLibrary()
        shell.openLibrary()
        XCTAssertTrue(shell.favoritesOnly, "📚 comes back to Favorites")
    }

    func testTheTabIsRememberedWithTheSurface() {
        let shell = ShellState(memory: store, restores: true)
        shell.showFavorites()
        XCTAssertTrue(ShellState(memory: store, restores: true).favoritesOnly, "reopened on Favorites")
        XCTAssertFalse(ShellState(memory: store, restores: false).favoritesOnly, "a launch that doesn't restore starts on Everything")

        store.clear()
        XCTAssertFalse(ShellState(memory: store, restores: true).favoritesOnly, "a fresh install: Everything")
    }
}
