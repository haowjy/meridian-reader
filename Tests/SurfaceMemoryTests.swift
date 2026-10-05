import XCTest
@testable import Reader

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

    func testWithoutRestoringItStartsOnTheBrowser() {
        store.save(SurfaceMemory(base: .library, libraryPath: [], browserURL: nil))
        XCTAssertTrue(ShellState(memory: store, restores: false).isBrowsing)
        XCTAssertTrue(ShellState().isBrowsing, "no memory: as before")
    }
}
