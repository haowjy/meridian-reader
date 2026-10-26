import XCTest
@testable import MeridianReader

/// Listen's floating ‹ (`ShellState.cameFrom`): back to the destination Listen was entered from, with
/// its place intact; none on a cold launch straight to Listen; cleared once used or once Listen is left.
@MainActor
final class ListenBackTests: XCTestCase {
    func testBackReturnsToTheLibraryWithItsPathIntact() {
        let shell = ShellState()
        let folder = LibraryRoute.folder(UUID())
        shell.showLibrary(at: [folder])
        shell.showNowPlaying()
        XCTAssertEqual(shell.chromeDestination, .reader)
        XCTAssertEqual(shell.listenBackTarget, .library)

        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .library)
        XCTAssertEqual(shell.libraryPath, [folder], "the folder it was in")
        XCTAssertNil(shell.listenBackTarget, "cleared once used")
    }

    func testBackReturnsToTheBrowser() {
        let shell = ShellState()
        shell.showBrowser()
        shell.showNowPlaying()
        XCTAssertEqual(shell.listenBackTarget, .browse)
        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .browse)
        XCTAssertFalse(shell.isNowPlayingPresented)
    }

    func testAColdLaunchStraightToListenHasNoBack() {
        let shell = ShellState()
        shell.showBrowser()
        shell.resumeNowPlayingAtLaunch()
        XCTAssertEqual(shell.chromeDestination, .reader)
        XCTAssertNil(shell.listenBackTarget)
        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .reader, "nothing to go back to")
    }

    func testEnteringListenAgainKeepsTheFirstPlaceAndLeavingByThePillClearsIt() {
        let shell = ShellState()
        shell.openLibrary()
        shell.showNowPlaying()
        shell.showNowPlaying()
        XCTAssertEqual(shell.listenBackTarget, .library, "already on Listen: not recorded again")
        shell.showBrowser()
        XCTAssertNil(shell.cameFrom, "left Listen another way")
        shell.showNowPlaying()
        XCTAssertEqual(shell.listenBackTarget, .browse, "the place it is entered from now")
    }

    func testTheOriginLabelNamesTheTitleAndThePlace() {
        XCTAssertEqual(ListenOrigin.library(path: []).label(title: "Tides"), "Open Tides in Library")
        XCTAssertEqual(ListenOrigin.browser(URL(string: "https://example.com/")!).label(title: "Tides"), "Open Tides in Browser")
    }
}
