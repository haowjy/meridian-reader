import XCTest

/// Lookups shared by the Library's UI tests.
extension XCTestCase {
    /// The Library on the demo article, book and folders, the Apple voice, no favorites.
    func launchLibrary(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoBook", "-seedDemoFolders", "-resetBookmarks",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"] + extra + ["-openLibrary"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10), "the Library")
        return app
    }

    /// The title of a row in a Library list: its label is the title and its value the status
    /// (which a Continue card's inner text, with the same title, doesn't have).
    func libraryRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells.staticTexts.matching(rowPredicate(title)).firstMatch
    }

    /// The cell holding the row titled `title`.
    func libraryCell(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "elementType == %d AND label == %@ AND value LIKE '?*'",
                                         XCUIElement.ElementType.staticText.rawValue, title)).firstMatch
    }

    private func rowPredicate(_ title: String) -> NSPredicate {
        NSPredicate(format: "label == %@ AND value LIKE '?*'", title)
    }

    /// Opens the folder row `title` and waits for its screen.
    func openFolder(_ app: XCUIApplication, _ title: String) {
        let row = libraryRow(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "folder \(title)")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title)'s screen")
    }

    /// ‹ closes the Reader sheet; waits until it has gone (the surface under it takes taps only
    /// then).
    func closeReader(_ app: XCUIApplication) {
        app.buttons["readerClose"].tap()
        XCTAssertTrue(eventually(5) { !app.buttons["readerClose"].exists }, "the Reader closed")
        idle(1)
    }

    /// Taps a row of the open ⋯ panel once the morph has finished growing.
    func tapMenuRow(_ app: XCUIApplication, _ id: String) {
        let row = find(app, id)
        XCTAssertTrue(row.waitForExistence(timeout: 3), "⋯ row \(id)")
        idle(0.6)
        row.tap()
    }

    /// Types `name` into the open New Folder alert and creates it.
    func createFolder(_ app: XCUIApplication, named name: String) {
        let alert = app.alerts["New Folder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "New Folder alert")
        alert.textFields.firstMatch.typeText(name)
        alert.buttons["Create"].firstMatch.tap()
    }

    /// Picks the folder `name` in the open Move tree (swiping up first when it is below the
    /// sheet's medium size).
    func pickInMoveTree(_ app: XCUIApplication, _ name: String) {
        let tree = find(app, "moveTree")
        XCTAssertTrue(tree.waitForExistence(timeout: 5), "the Move tree")
        let folder = app.buttons.matching(identifier: "moveFolder").matching(NSPredicate(format: "label == %@", name)).firstMatch
        if !folder.waitForExistence(timeout: 1) {
            tree.swipeUp()
            idle(0.8)
        }
        XCTAssertTrue(folder.waitForExistence(timeout: 3), "\(name) in the Move tree")
        folder.tap()
    }
}
