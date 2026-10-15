import XCTest

/// *Delete Folder and Contents* on a full folder: its pages, a subfolder with a page, a book and
/// the page that is playing all go at once, from the folder's row on the screen above it and from
/// the folder's own screen; the app stays up and the Library shows what is left. A swipe that
/// asks first leaves its row in the list until the delete is saved: *Cancel*, or a delete that
/// can't be saved, keeps it. Offline: the demo folders, the demo book, the Apple voice.
final class FolderDeleteUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Swipe → *Delete* on the home's row of a folder holding a book, a subfolder and the page
    /// that is playing.
    func testDeletingAFullPlayingFolderFromItsRow() throws {
        let app = launchLibrary()
        fillAndPlayDemoFinance(app)
        app.navigationBars["Demo Finance"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "the home")

        let row = libraryCell(app, "Demo Finance")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "the row's swipe action")
        delete.tap()
        confirmDeleteWithContents(app)

        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Demo Finance").exists }, "Demo Finance is gone")
        assertDemoFinanceGone(app)
    }

    /// ⋯ → *Delete Folder…* on the folder's own screen: the screen goes, back to the home.
    func testDeletingAFullPlayingFolderFromItsScreen() throws {
        let app = launchLibrary()
        fillAndPlayDemoFinance(app)

        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreDeleteFolder")
        confirmDeleteWithContents(app)

        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5), "back to the home")
        XCTAssertTrue(eventually(5) { !self.libraryRow(app, "Demo Finance").exists }, "Demo Finance is gone")
        assertDemoFinanceGone(app)
    }

    /// Swipe → *Delete* → *Cancel*: nothing is deleted and the row stays (a swipe action that
    /// asks first must not take the row out of the list before the answer), and it still opens.
    func testCancellingASwipedDeleteKeepsTheRow() throws {
        let app = launchLibrary()
        let row = libraryCell(app, "Demo Finance")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "the row's swipe action")
        delete.tap()
        let all = app.buttons["deleteFolderAndContents"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 3), "the delete question")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(eventually(3) { !all.exists }, "cancelled")
        idle(1)
        XCTAssertTrue(libraryRow(app, "Demo Finance").exists, "the row stays")
        openFolder(app, "Demo Finance")
        XCTAssertTrue(libraryRow(app, "Bonds").waitForExistence(timeout: 5), "with its contents")
        app.navigationBars["Demo Finance"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground, "the app is still up")
    }

    /// A swiped *Remove* or *Delete* that can't be saved changes nothing: a toast says so, and
    /// the row stays in its list (the swipe doesn't take it out ahead of the save).
    func testSwipedRemovesAndDeletesThatCantBeSavedKeepTheirRows() throws {
        let app = launchLibrary(["-failLibrarySaves"])
        let toast = find(app, "toast")
        let cell = libraryCell(app, "Demo Listen Article")
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Pages: the demo article")
        cell.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "the page row's swipe action")
        remove.tap()
        XCTAssertTrue(eventually(5) { toast.exists && toast.label == "Couldn’t remove" }, "the toast says so")
        XCTAssertTrue(eventually(10) { !toast.exists }, "the toast went")
        XCTAssertTrue(libraryRow(app, "Demo Listen Article").exists, "the page's row stays")

        let row = libraryCell(app, "Demo Finance")
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "the folder row's swipe action")
        delete.tap()
        confirmDeleteWithContents(app)
        XCTAssertTrue(eventually(5) { toast.exists && toast.label == "Couldn’t delete" }, "the toast says so")
        idle(1)
        XCTAssertTrue(libraryRow(app, "Demo Finance").exists, "the folder's row stays")
        openFolder(app, "Demo Finance")
        XCTAssertTrue(libraryRow(app, "Bonds").waitForExistence(timeout: 5), "with its contents")
        XCTAssertEqual(app.state, .runningForeground, "the app is still up")
    }

    /// Swipe → *Remove* on a page that has been played: it leaves the Library and its row comes
    /// back in the same list as "Not saved" (played without saving). The swipe doesn't take the
    /// row out ahead of the data, so the List and the library agree and the app stays up.
    func testSwipeRemovingAPlayedPageKeepsItsRowAsNotSaved() throws {
        let app = launchLibrary()
        let cell = libraryCell(app, "Demo Listen Article")
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Pages: the demo article")
        cell.buttons["Play"].tap()
        let bar = app.buttons["nowPlayingBarPlayPause"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar shows what you hear")
        XCTAssertTrue(eventually(10) { bar.label == "Pause" }, "playing")

        cell.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "the page row's swipe action")
        remove.tap()
        let row = libraryRow(app, "Demo Listen Article")
        XCTAssertTrue(eventually(5) { (row.value as? String)?.contains("Not saved") == true },
                      "back in the list as Not saved, got \(row.value ?? "nil")")
        idle(1)
        XCTAssertEqual(app.state, .runningForeground, "the app is still up")
        XCTAssertTrue(libraryRow(app, "Demo Finance").exists, "the rest of the list is there")
        XCTAssertEqual(bar.label, "Pause", "Remove never touches playback")
    }

    // MARK: - Steps

    /// Moves the demo book into Demo Finance (beside its pages and its subfolders Bonds and
    /// Taxes), then plays Demo Finance from its first page, and stays on Demo Finance's screen.
    private func fillAndPlayDemoFinance(_ app: XCUIApplication) {
        openFolder(app, "The Demo Book")
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreMove")
        pickInMoveTree(app, "Demo Finance")
        XCTAssertTrue(app.navigationBars["The Demo Book"].waitForExistence(timeout: 5), "the book, in Demo Finance")
        app.navigationBars["The Demo Book"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Demo Finance"].waitForExistence(timeout: 5))
        XCTAssertTrue(libraryRow(app, "The Demo Book").waitForExistence(timeout: 5), "the book's row")
        XCTAssertTrue(libraryRow(app, "Bonds").exists, "a subfolder's row")

        app.buttons["folderPlayFromStart"].tap()
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(eventually(10) { bar.label.contains("Seven-Day Yield") }, "a page inside plays: \(bar.label)")
    }

    private func confirmDeleteWithContents(_ app: XCUIApplication) {
        let all = app.buttons["deleteFolderAndContents"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 3), "Delete Folder and Contents")
        all.tap()
    }

    /// The app is still up on the home, without the folder, its book or its pages, and nothing
    /// inside it plays.
    private func assertDemoFinanceGone(_ app: XCUIApplication) {
        idle(1)
        XCTAssertEqual(app.state, .runningForeground, "the app is still up")
        XCTAssertTrue(app.libraryHome.exists, "the home")
        XCTAssertFalse(libraryRow(app, "The Demo Book").exists, "the book went with it")
        XCTAssertFalse(libraryRow(app, "Seven-Day Yield").exists, "and its pages")
        let bar = find(app, "nowPlayingBarOpen")
        XCTAssertFalse(bar.exists && bar.label.contains("Seven-Day Yield"), "the deleted page no longer plays")
    }
}
