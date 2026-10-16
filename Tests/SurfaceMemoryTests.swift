import XCTest
@testable import MeridianReader

/// Decision D10: the shell remembers the surface you left (the Library with its path, or the
/// browser and its page) and reopens on it; with nothing remembered (a fresh install) it opens
/// the Library. Folders that no longer exist drop off the path.
@MainActor
final class SurfaceMemoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SurfaceMemoryStore!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SurfaceMemoryTests-\(UUID())")
        store = SurfaceMemoryStore(defaults: defaults)
    }

    func testAFreshInstallOpensTheLibrary() {
        let shell = ShellState(memory: store, restores: true)
        XCTAssertTrue(shell.isInLibrary)
        XCTAssertEqual(shell.libraryPath, [])
    }

    func testTheLibraryAndItsPathAreRememberedAndRestored() {
        let a = UUID(), b = UUID()
        let shell = ShellState(memory: store, restores: true)
        shell.libraryPath = [.folder(a), .folder(b)]
        XCTAssertEqual(store.load()?.base, .library)
        XCTAssertEqual(store.load()?.libraryPath, [.folder(a), .folder(b)])

        let reopened = ShellState(memory: store, restores: true)
        XCTAssertTrue(reopened.isInLibrary)
        XCTAssertEqual(reopened.libraryPath, [.folder(a), .folder(b)])
    }

    func testFoldersThatAreGoneDropOffThePath() {
        let kept = UUID(), gone = UUID(), below = UUID()
        store.save(SurfaceMemory(base: .library, libraryPath: [.folder(kept), .folder(gone), .folder(below)],
                                 browserURL: nil))
        let shell = ShellState(memory: store, restores: true)
        shell.restoreAtLaunch { $0 == kept || $0 == below }
        XCTAssertEqual(shell.libraryPath, [.folder(kept)], "up to the first that's gone")
    }

    func testLeavingForTheBrowserIsRememberedAndTheLibraryKeepsItsPlace() {
        let folder = UUID()
        let shell = ShellState(memory: store, restores: true)
        shell.libraryPath = [.folder(folder)]
        shell.leaveLibrary()
        XCTAssertEqual(store.load()?.base, .browse)
        XCTAssertEqual(store.load()?.libraryPath, [.folder(folder)], "the Library's place is kept")

        let reopened = ShellState(memory: store, restores: true)
        XCTAssertTrue(reopened.isBrowsing)
        reopened.openLibrary()
        XCTAssertEqual(reopened.libraryPath, [.folder(folder)])
    }

    /// Reopened on the Library, the browser's page waits for 🌐 (no WebKit at a cold launch):
    /// the launch's restore keeps it, and the first trip to the browser loads it. Relaunching
    /// again before that still remembers it.
    func testReopenedOnTheLibraryTheBrowsersPageLoadsWhenYouGoThere() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/story"))
        store.save(SurfaceMemory(base: .library, libraryPath: [], browserURL: url.absoluteString))
        let shell = ShellState(memory: store, restores: true)
        shell.restoreAtLaunch { _ in true }
        XCTAssertTrue(shell.isInLibrary)
        XCTAssertNil(shell.web.currentURL, "nothing loads under the Library")
        shell.libraryPath = [.folder(UUID())]
        XCTAssertEqual(store.load()?.browserURL, url.absoluteString, "still remembered")

        let again = ShellState(memory: store, restores: true)
        again.restoreAtLaunch { _ in true }
        again.leaveLibrary()
        XCTAssertTrue(again.isBrowsing)
        XCTAssertEqual(again.web.currentURL, url, "🌐: the browser's page, as it was left")
    }

    func testWithoutRestoringItStartsOnTheBrowser() {
        store.save(SurfaceMemory(base: .library, libraryPath: [], browserURL: nil))
        XCTAssertTrue(ShellState(memory: store, restores: false).isBrowsing)
        XCTAssertTrue(ShellState().isBrowsing, "no memory: as before")
    }

    /// A stored path can name a screen this version doesn't have (the top level's own pages
    /// screen): that element is dropped and the rest still opens, instead of the whole memory
    /// failing to decode.
    func testAStoredPathDropsAScreenItDoesNotKnow() throws {
        let folder = UUID()
        let json = """
        {"base":"library","libraryPath":[{"folder":{"_0":"\(folder.uuidString)"}},{"pages":{}}],\
        "browserURL":"https://example.com/story"}
        """
        defaults.set(Data(json.utf8), forKey: SurfaceMemoryStore.key)
        let memory = try XCTUnwrap(store.load())
        XCTAssertEqual(memory.base, .library)
        XCTAssertEqual(memory.libraryPath, [.folder(folder)])
        XCTAssertEqual(memory.browserURL, "https://example.com/story")

        let shell = ShellState(memory: store, restores: true)
        XCTAssertTrue(shell.isInLibrary)
        XCTAssertEqual(shell.libraryPath, [.folder(folder)])
    }

    /// The encoding of a path is unchanged: what this version writes, it reads back.
    func testAPathRoundTrips() {
        let a = UUID(), b = UUID()
        store.save(SurfaceMemory(base: .browse, libraryPath: [.folder(a), .folder(b)], browserURL: nil))
        XCTAssertEqual(store.load(), SurfaceMemory(base: .browse, libraryPath: [.folder(a), .folder(b)], browserURL: nil))
    }
}
