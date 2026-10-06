import XCTest

/// Saves and edits that can't be stored (`-failLibrarySaves`: every library save fails once the
/// app has launched): each says "Couldn’t …" where it was asked for (a book import says it in the
/// import sheet's one line), nothing reads as done, and what was open stays open. Offline: the
/// test pages and the demo folders.
final class SaveFailureUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Waits for the toast to say `message`.
    private func expectToast(_ app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let toast = find(app, "toast")
        XCTAssertTrue(eventually(5) { toast.exists && toast.label == message }, "the toast says “\(message)”",
                      file: file, line: line)
    }

    /// Waits for the toast to go, so the next one is a new one.
    private func expectNoToast(_ app: XCUIApplication) {
        XCTAssertTrue(eventually(10) { !self.find(app, "toast").exists }, "the toast went")
    }

    /// The toast floats over the Move tree, which stays up until ✕.
    private func expectTheTreeStaysUnderTheToast(_ app: XCUIApplication, _ message: String) {
        let tree = find(app, "moveTree")
        expectToast(app, message)
        idle(1)
        XCTAssertTrue(tree.exists, "the Move tree stays up")
        let toast = find(app, "toast").frame
        XCTAssertTrue(tree.frame.contains(CGPoint(x: toast.midX, y: toast.midY)), "the toast is over the tree: \(toast) in \(tree.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "move-tree-under-\(message)"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["moveCancel"].tap()
        XCTAssertTrue(eventually(5) { !tree.exists }, "✕ closes it")
    }

    /// Every way to save a page: the browser's ⋯ → Save to Library…, the Reader's 🔖 and *Save
    /// to Folder…*, Now Playing's ⊕. Each says "Couldn’t save", and the page stays unsaved.
    func testASaveThatCantBeStoredSaysSoAndThePageStaysUnsaved() throws {
        let app = launchTestPages(["-seedDemoArticle", "-failLibrarySaves"])
        openTestPage(app, "Next page")

        app.buttons["browseMore"].tap()
        tapMenuRow(app, "moreSave")
        pickInMoveTree(app, topLevel: true)
        XCTAssertTrue(eventually(5) { !self.find(app, "moveTree").exists }, "the tree closes as the page is extracted")
        expectToast(app, "Couldn’t save")
        expectNoToast(app)
        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        idle(1)
        XCTAssertFalse(libraryRow(app, "Second page").exists, "not in the Library")
        app.buttons["libraryBrowser"].tap()

        find(app, "addressReader").tap()
        let bookmark = app.buttons["readerBookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        bookmark.tap()
        expectToast(app, "Couldn’t save")
        XCTAssertEqual(bookmark.value as? String, "Not saved", "🔖 doesn't fill")
        expectNoToast(app)

        bookmark.press(forDuration: 1.0)
        pickInMoveTree(app, topLevel: true)
        expectTheTreeStaysUnderTheToast(app, "Couldn’t save")
        XCTAssertEqual(bookmark.value as? String, "Not saved")
        expectNoToast(app)

        app.buttons["listenPlayPause"].tap()
        XCTAssertTrue(find(app, "nowPlayingFrom").waitForExistence(timeout: 10), "Now Playing")
        let plus = app.buttons["readerBookmark"]
        XCTAssertEqual(plus.value as? String, "Not saved")
        plus.tap()
        expectToast(app, "Couldn’t save")
        XCTAssertEqual(plus.value as? String, "Not saved", "⊕ stays ⊕")
        find(app, "listenPlayPause").tap()
    }

    /// Edit in a folder, on a subfolder: Remove → Cancel keeps it selected; a delete that can't be
    /// stored keeps the folder, Edit and the selection (Remove asks again); a move that can't be
    /// stored keeps the Move tree up under its toast, and the selection.
    func testEditKeepsItsSelectionAndTheMoveTreeWhenNothingCanBeStored() throws {
        let app = launchLibrary(["-failLibrarySaves"])
        openFolder(app, "Demo Finance")
        app.buttons["folderEdit"].tap()
        libraryRow(app, "Bonds").tap()
        let remove = app.buttons["editRemove"]
        XCTAssertTrue(eventually(3) { remove.isEnabled }, "Bonds selected")

        remove.tap()
        let folderOnly = app.buttons["deleteFolderOnly"].firstMatch
        XCTAssertTrue(folderOnly.waitForExistence(timeout: 3), "the delete question")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(eventually(3) { !folderOnly.exists }, "cancelled")
        XCTAssertTrue(remove.isEnabled, "Cancel keeps Bonds selected")

        remove.tap()
        XCTAssertTrue(folderOnly.waitForExistence(timeout: 3), "Remove asks again")
        folderOnly.tap()
        expectToast(app, "Couldn’t delete")
        XCTAssertTrue(libraryRow(app, "Bonds").exists, "Bonds stays")
        XCTAssertTrue(remove.isEnabled, "still in Edit, Bonds still selected")
        expectNoToast(app)

        app.buttons["editMove"].tap()
        pickInMoveTree(app, topLevel: true)
        expectTheTreeStaysUnderTheToast(app, "Couldn’t move")
        XCTAssertTrue(app.buttons["editMove"].isEnabled, "Bonds still selected")
        XCTAssertTrue(libraryRow(app, "Bonds").exists, "and in Demo Finance")
    }

    /// A book from an `.epub` link while nothing can be stored: *New Folder* in *Add to*'s tree
    /// says "Couldn’t make the folder" over the tree, inside the import sheet, and the tree stays
    /// up with *Add to* unchanged; *Import* then says the book couldn't be saved, in the sheet's
    /// one line with OK, and keeps nothing.
    func testABookThatCantBeStoredSaysSoInTheImportSheet() throws {
        let app = launchTestPages(["-seedDemoFolders", "-importTestEPUB", "-failLibrarySaves"])
        let link = app.links["Download a book"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "page one links to a book")
        link.tap()
        XCTAssertTrue(find(app, "importSheet").waitForExistence(timeout: 15), "the import sheet")
        let start = app.buttons["importStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 3), "it waits for Import")
        expectNoToast(app)

        let change = app.buttons["importChange"]
        change.tap()
        let tree = find(app, "importAddToTree")
        XCTAssertTrue(tree.waitForExistence(timeout: 5), "Add to's tree, in the sheet")
        app.buttons["moveNewFolder"].tap()
        createFolder(app, named: "Essays")
        expectToast(app, "Couldn’t make the folder")
        idle(1)
        XCTAssertTrue(tree.exists, "the tree stays up")
        let toast = find(app, "toast").frame
        XCTAssertTrue(tree.frame.contains(CGPoint(x: toast.midX, y: toast.midY)), "the toast is over the tree: \(toast) in \(tree.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "import-add-to-under-couldnt-make-the-folder"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(moveTreeFolder(app, "Essays").exists, "no folder")

        app.navigationBars["Add to"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "back on the sheet")
        XCTAssertTrue(change.label.contains("Library"), "Add to unchanged: \(change.label)")
        start.tap()
        let failure = app.alerts["Meridian couldn't save the book. Try again."]
        XCTAssertTrue(failure.waitForExistence(timeout: 30), "the sheet says the book couldn't be saved")
        app.buttons["importFailureOK"].firstMatch.tap()
        XCTAssertTrue(eventually(5) { !self.find(app, "importSheet").exists }, "OK closes the sheet")

        app.buttons["browseLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        idle(1)
        XCTAssertFalse(libraryRow(app, "The Imported Demo Book").exists, "no book in the Library")
    }
}
