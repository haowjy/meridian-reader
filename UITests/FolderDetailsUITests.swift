import XCTest

/// *Edit Details* on a plain folder: from the folder's ⋯ and from its row's long-press menu. A
/// name, an author and a cover give it a book's header (the cover beside the title, the author
/// before the counts, the bar and buttons on the cards' edges); clearing them gives it the plain
/// header back. `-pickTestCover` stands in for the Files picker. Offline: the demo folders.
///
/// With `TEST_RUNNER_READER_SCREENSHOTS_DIR=<dir>` each step's screen is also saved under
/// `<dir>/FolderDetails/`.
final class FolderDetailsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testEditDetailsFromTheMenuGivesAFolderABooksHeaderAndClearingRevertsIt() throws {
        let app = launchLibrary(["-pickTestCover"])
        openFolder(app, "Demo Finance")
        XCTAssertEqual(headerLook(app), "plain", "no details yet")

        openEditDetailsFromMenu(app)
        shot("sheet-empty")
        replaceText(in: find(app, "detailsName"), with: "Tide Tables")
        replaceText(in: find(app, "detailsAuthor"), with: "A. Writer")
        find(app, "detailsCoverFiles").tap()
        XCTAssertTrue(eventually(5) { self.find(app, "detailsCover").label == "Cover" }, "the picked cover shows")
        XCTAssertTrue(find(app, "detailsRemoveCover").exists, "Remove Cover, once there is one")
        shot("sheet-filled")
        find(app, "detailsSave").tap()

        XCTAssertTrue(app.navigationBars["Tide Tables"].waitForExistence(timeout: 5), "renamed")
        XCTAssertTrue(eventually(5) { self.headerLook(app) == "detailed with cover" }, "a book's header: \(headerLook(app))")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A. Writer")).firstMatch.exists,
                      "the author in the header")
        assertHeaderOnTheCardsEdges(app)
        shot("folder-detailed")

        app.navigationBars["Tide Tables"].buttons.firstMatch.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))
        XCTAssertTrue(libraryRow(app, "Tide Tables").waitForExistence(timeout: 5), "the row, renamed")
        shot("home-row")

        openFolder(app, "Tide Tables")
        openEditDetailsFromMenu(app)
        XCTAssertEqual(find(app, "detailsAuthor").value as? String, "A. Writer", "the sheet starts from the details")
        find(app, "detailsRemoveCover").tap()
        replaceText(in: find(app, "detailsAuthor"), with: "")
        find(app, "detailsSave").tap()
        XCTAssertTrue(eventually(5) { self.headerLook(app) == "plain" }, "the plain header again: \(headerLook(app))")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "A. Writer")).firstMatch.exists)
        XCTAssertTrue(app.buttons["folderContinue"].exists, "still plays like a book")
        shot("folder-cleared")
    }

    /// The row's long-press menu opens the same sheet; an author alone gives the folder a book's
    /// header with a letter tile. Cancel changes nothing.
    func testEditDetailsFromARowsLongPress() throws {
        let app = launchLibrary()
        openEditDetailsFromRow(app, "Demo Finance")
        replaceText(in: find(app, "detailsAuthor"), with: "Someone Else")
        find(app, "detailsCancel").tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "folderDetailsSheet").exists }, "Cancel closes it")
        openFolder(app, "Demo Finance")
        XCTAssertEqual(headerLook(app), "plain", "Cancel saved nothing")
        app.navigationBars["Demo Finance"].buttons.firstMatch.tap()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 5))

        openEditDetailsFromRow(app, "Demo Finance")
        replaceText(in: find(app, "detailsAuthor"), with: "A. Writer")
        find(app, "detailsSave").tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "folderDetailsSheet").exists }, "Save closes it")
        openFolder(app, "Demo Finance")
        XCTAssertTrue(eventually(5) { self.headerLook(app) == "detailed" }, "an author alone: \(headerLook(app))")
        shot("folder-author-only")
    }

    // MARK: - Steps

    private func openEditDetailsFromMenu(_ app: XCUIApplication) {
        app.buttons["libraryMore"].tap()
        tapMenuRow(app, "moreEditDetails")
        XCTAssertTrue(find(app, "folderDetailsSheet").waitForExistence(timeout: 5), "Edit Details")
    }

    private func openEditDetailsFromRow(_ app: XCUIApplication, _ title: String) {
        let row = libraryRow(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row \(title)")
        row.press(forDuration: 1.0)
        let edit = app.buttons["Edit Details"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "the row's menu")
        edit.tap()
        XCTAssertTrue(find(app, "folderDetailsSheet").waitForExistence(timeout: 5), "Edit Details")
    }

    private func headerLook(_ app: XCUIApplication) -> String {
        let marker = find(app, "folderHeaderLook")
        _ = marker.waitForExistence(timeout: 5)
        return marker.value as? String ?? "none"
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let current = field.value as? String ?? ""
        let placeholder = field.placeholderValue ?? ""
        if !current.isEmpty, current != placeholder {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !text.isEmpty { field.typeText(text) }
    }

    /// The detailed header keeps 46ce36b's edges: the bar and the button row span the cards'
    /// width, and the percent and time left sit on one line.
    private func assertHeaderOnTheCardsEdges(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let progress = find(app, "folderHeaderProgress")
        XCTAssertTrue(progress.waitForExistence(timeout: 5), "the progress block", file: file, line: line)
        let card = libraryCell(app, "Index Funds")
        XCTAssertTrue(card.waitForExistence(timeout: 5), file: file, line: line)
        let bar = progress.frame, play = app.buttons["folderContinue"].frame
        let fromStart = app.buttons["folderPlayFromStart"].frame
        XCTAssertEqual(bar.minX, card.frame.minX, accuracy: 1, "bar leading edge", file: file, line: line)
        XCTAssertEqual(bar.maxX, card.frame.maxX, accuracy: 1, "bar trailing edge", file: file, line: line)
        XCTAssertEqual(play.minX, card.frame.minX, accuracy: 1, "Continue leading edge", file: file, line: line)
        XCTAssertEqual(fromStart.maxX, card.frame.maxX, accuracy: 1, "Play from Start trailing edge", file: file, line: line)
        XCTAssertLessThan(bar.height, 36, "percent and time left on one line", file: file, line: line)
        XCTAssertFalse(progress.label.contains("·"), "no dot: \(progress.label)", file: file, line: line)
    }

    private func shot(_ name: String) {
        guard let path = ProcessInfo.processInfo.environment["READER_SCREENSHOTS_DIR"], !path.isEmpty else { return }
        let dir = URL(fileURLWithPath: path).appendingPathComponent("FolderDetails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
