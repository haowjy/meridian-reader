import XCTest
@testable import MeridianReader

/// Listen's floating ‹ (`ShellState.listenLaunch`): back to the place that LAUNCHED the listening, not
/// the last other screen; set only by a launch, never by switching destinations, kept by ‹.
@MainActor
final class ListenBackTests: XCTestCase {
    private func browserShell(_ page: String = "https://example.com/story") -> ShellState {
        let defaults = UserDefaults(suiteName: "ListenBackTests.\(UUID())")!
        SurfaceMemoryStore(defaults: defaults).save(SurfaceMemory(base: .browse, libraryPath: [], browserURL: page))
        return ShellState(memory: SurfaceMemoryStore(defaults: defaults), restores: true)
    }

    func testBackReturnsToTheLibraryItWasLaunchedFromWithItsPathIntact() {
        let shell = ShellState()
        let folder = LibraryRoute.folder(UUID())
        shell.showLibrary(at: [folder])
        shell.noteLaunch()
        shell.showNowPlaying()
        XCTAssertEqual(shell.chromeDestination, .reader)
        XCTAssertNotNil(shell.listenBackTarget)

        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .library)
        XCTAssertEqual(shell.libraryPath, [folder], "the folder it was launched in")
        XCTAssertFalse(shell.isNowPlayingPresented)
        XCTAssertNil(shell.listenBackTarget, "off Listen there is no ‹")
        XCTAssertNotNil(shell.listenLaunch, "‹ keeps the record")
    }

    func testLibraryToBrowserToListenViaTheTabStillGoesBackToTheLibrary() {
        let shell = ShellState()
        let folder = LibraryRoute.folder(UUID())
        shell.showLibrary(at: [folder])
        shell.homeTab = .favorites
        shell.noteLaunch()
        shell.showNowPlaying()
        shell.showBrowser()
        XCTAssertEqual(shell.chromeDestination, .browse)
        shell.showNowPlaying()
        XCTAssertNotNil(shell.listenBackTarget, "switching tabs never overwrote the launch")

        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .library, "back to where it was launched, not the Browser")
        XCTAssertEqual(shell.libraryPath, [folder])
        XCTAssertEqual(shell.homeTab, .favorites)
    }

    func testRepeatedVisitsKeepWorking() {
        let shell = ShellState()
        shell.openLibrary()
        shell.noteLaunch()
        for _ in 0..<3 {
            shell.showNowPlaying()
            XCTAssertNotNil(shell.listenBackTarget)
            shell.backFromListen()
            XCTAssertEqual(shell.chromeDestination, .library)
            shell.showBrowser()
        }
    }

    func testANewLaunchReplacesTheRecord() {
        let shell = browserShell()
        let folder = LibraryRoute.folder(UUID())
        shell.showLibrary(at: [folder])
        shell.noteLaunch()
        shell.showBrowser()
        shell.noteLaunch()
        shell.showNowPlaying()
        shell.openLibrary()
        shell.showNowPlaying()
        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .browse, "the later launch, from the Browser")
    }

    func testLaunchFromListenItselfDoesNotReplaceIt() {
        let shell = ShellState()
        shell.openLibrary()
        shell.noteLaunch()
        shell.showNowPlaying()
        shell.noteLaunch()
        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .library)
    }

    func testBackReturnsToTheBrowserPageItWasLaunchedFrom() {
        let shell = browserShell()
        XCTAssertEqual(shell.chromeDestination, .browse)
        shell.noteLaunch()
        shell.showNowPlaying()
        shell.openLibrary()
        shell.showNowPlaying()
        XCTAssertNotNil(shell.listenBackTarget)
        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .browse)
        XCTAssertFalse(shell.isNowPlayingPresented)
    }

    func testNoRecordHidesBack() {
        let shell = ShellState()
        shell.openLibrary()
        shell.showNowPlaying()
        XCTAssertEqual(shell.chromeDestination, .reader)
        XCTAssertNil(shell.listenBackTarget, "opened by the tab with nothing launched")
        shell.backFromListen()
        XCTAssertEqual(shell.chromeDestination, .reader, "nothing to go back to")
    }

    func testACrashResumeKeepsTheSavedRecord() {
        let shell = browserShell()
        shell.noteLaunch()
        shell.resumeNowPlayingAtLaunch()
        XCTAssertEqual(shell.chromeDestination, .reader)
        XCTAssertNotNil(shell.listenBackTarget, "a resume keeps where it was launched from")
    }

    func testALaunchWithNoPageLoadedKeepsTheSavedRecord() {
        let shell = ShellState()
        let folder = LibraryRoute.folder(UUID())
        shell.showLibrary(at: [folder])
        shell.noteLaunch()
        shell.showBrowser()
        shell.noteLaunch()
        XCTAssertEqual(shell.listenLaunch?.origin, .library(path: [folder]),
                       "a browser with nothing loaded names no place, so the saved one stays")
    }

    func testNothingEverLaunchedHasNoBack() {
        let shell = browserShell()
        shell.resumeNowPlayingAtLaunch()
        XCTAssertNil(shell.listenBackTarget)
    }

    func testTheStoredRecordRoundTripsThroughJSON() throws {
        let folder = UUID(), reading = UUID()
        var library = ListenLaunch(place: .library(path: [.folder(folder)], tab: .favorites, reading: nil))
        library.readingKey = reading
        var browser = ListenLaunch(place: .browser(url: URL(string: "https://www.reddit.com/r/x")!, reading: nil), scrollY: 1234)
        browser.wasReading = true
        for launch in [library, browser] {
            let data = try JSONEncoder().encode(launch.stored)
            let back = try JSONDecoder().decode(ListenLaunch.Stored.self, from: data)
            XCTAssertEqual(back, launch.stored)
            XCTAssertEqual(ListenLaunch(stored: back)?.stored, launch.stored)
        }
        XCTAssertEqual(ListenLaunch(stored: library.stored)?.origin, .library(path: [.folder(folder)]))
        XCTAssertEqual(ListenLaunch(stored: browser.stored)?.scrollY, 1234)
    }

    func testTheRecordSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "ListenBackTests.\(UUID())")!
        let store = SurfaceMemoryStore(defaults: defaults)
        store.save(SurfaceMemory(base: .browse, libraryPath: [], browserURL: "https://example.com/story"))
        let before = ShellState(memory: store, restores: true)
        before.noteLaunch()
        before.showNowPlaying()

        // A relaunch: a new shell from the same defaults, now on the Library.
        store.save(SurfaceMemory(base: .library, libraryPath: [], browserURL: nil))
        let after = ShellState(memory: store, restores: true)
        after.showNowPlaying()
        XCTAssertEqual(after.listenBackOrigin, .browser(URL(string: "https://example.com/story")!))
        after.backFromListen()
        XCTAssertEqual(after.chromeDestination, .browse)
        XCTAssertEqual(after.web.currentURL, URL(string: "https://example.com/story"))
    }

    func testALibraryRecordSurvivesARelaunchWithItsFolderTabAndRead() {
        let defaults = UserDefaults(suiteName: "ListenBackTests.\(UUID())")!
        let store = SurfaceMemoryStore(defaults: defaults)
        let folder = LibraryRoute.folder(UUID())
        let before = ShellState(memory: store, restores: true)
        before.showLibrary(at: [folder])
        before.homeTab = .favorites
        before.noteLaunch()

        let after = ShellState(memory: store, restores: true)
        after.showBrowser()
        after.showNowPlaying()
        after.backFromListen()
        XCTAssertEqual(after.chromeDestination, .library)
        XCTAssertEqual(after.libraryPath, [folder])
        XCTAssertEqual(after.homeTab, .favorites)
    }

    func testTheOriginLabelNamesTheTitleAndThePlace() {
        XCTAssertEqual(ListenOrigin.library(path: []).label(title: "Tides"), "Open Tides in Library")
        XCTAssertEqual(ListenOrigin.browser(URL(string: "https://example.com/")!).label(title: "Tides"), "Open Tides in Browser")
        let launch = ListenLaunch(place: .browser(url: URL(string: "https://example.com/")!, reading: nil))
        XCTAssertEqual(launch.origin.label(title: "Tides"), "Open Tides in Browser", "the title block shares the launch record")
    }

    func testADeletedLaunchFolderFallsBackToItsSurvivingParent() {
        let shell = ShellState()
        let parent = UUID(), gone = UUID()
        shell.showLibrary(at: [.folder(parent), .folder(gone)])
        shell.noteLaunch()
        shell.showNowPlaying()
        shell.backFromListen(folderExists: { $0 == parent })
        XCTAssertEqual(shell.libraryPath, [.folder(parent)])
        XCTAssertEqual(ShellState.surviving([.folder(gone), .folder(parent)], exists: { $0 == parent }), [], "the Library's home")
    }
}
