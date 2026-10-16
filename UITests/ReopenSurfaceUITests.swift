import XCTest

/// Decision D10: the app reopens on the surface you left. Left on the browser, it reopens there
/// on the same page; left on a folder, the Library at that folder; a fresh install opens the
/// Library. UI-test launches start on the browser unless `-restoreSurface`; the relaunches keep
/// what the first launch left (`UITestSetup.relaunch`).
final class ReopenSurfaceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLeftOnTheBrowserReopensOnItsPage() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        app.terminate()

        let again = launch(.relaunch(["-browseTestPages", "-restoreSurface"]))
        XCTAssertTrue(again.staticTexts["Second page"].waitForExistence(timeout: 10), "the browser, on its page")
        XCTAssertEqual(again.textFields["addressField"].value as? String, "pages/two")
        XCTAssertFalse(again.libraryHome.exists)
    }

    func testLeftOnAFolderReopensTheLibraryThere() throws {
        let app = launchLibrary()
        openFolder(app, "Demo Finance")
        openFolder(app, "Bonds")
        app.terminate()

        let again = launch(.relaunch(["-restoreSurface"]))
        XCTAssertTrue(again.navigationBars["Bonds"].waitForExistence(timeout: 10), "the Library at Bonds")
        again.navigationBars["Bonds"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(again.navigationBars["Demo Finance"].waitForExistence(timeout: 5), "under Demo Finance")
    }

    /// Browse a page, leave on the Library's Favorites tab: relaunched there, 🌐 shows the page
    /// you were on.
    func testLeftInTheLibraryTheGlobeReopensTheBrowsersPage() throws {
        let app = launchTestPages()
        openTestPage(app, "Next page")
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        app.buttons["Favorites"].tap()
        app.terminate()

        let again = launch(.relaunch(["-browseTestPages", "-restoreSurface"]))
        XCTAssertTrue(again.libraryHome.waitForExistence(timeout: 10), "the Library at Favorites")
        XCTAssertTrue(again.buttons["Favorites"].isSelected)
        again.buttons["libraryBrowser"].tap()
        XCTAssertTrue(again.staticTexts["Second page"].waitForExistence(timeout: 10), "🌐: the page you left")
        XCTAssertEqual(again.textFields["addressField"].value as? String, "pages/two")
    }

    func testAFreshInstallOpensTheLibrary() throws {
        let app = launch(["-restoreSurface"])
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10), "the Library home")
    }
}
