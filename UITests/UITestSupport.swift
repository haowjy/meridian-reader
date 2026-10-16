import XCTest

/// Launches, waits and lookups the UI tests share. Every launch starts as a fresh install would
/// (`-resetLibrary`: an empty library, the stored settings cleared), with the test markers on and
/// no network suggestions (`-uiTesting`) and the Apple voice, then adds `arguments`: the seeds and
/// other options of `App/LaunchOptions.swift`.
extension XCTestCase {
    @discardableResult
    func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetLibrary", "-selectEngine", "apple"] + arguments
        app.launch()
        return app
    }

    /// The Library on the demo article, book and folders.
    func launchLibrary() -> XCUIApplication {
        let app = launch(["-seedDemoArticle", "-seedDemoBook", "-seedDemoFolders", "-openLibrary"])
        XCTAssertTrue(appears(app.libraryHome, timeout: 10), "the Library")
        return app
    }

    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func idle(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            idle(0.1)
        }
        return condition()
    }

    /// Whether `element` exists within `timeout`, looked for every 0.1 s (`waitForExistence`
    /// looks once a second, so each call costs about a second even when it is already there).
    func appears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        eventually(timeout) { element.exists }
    }

    /// Taps `element` once it takes taps. After a sheet goes, what was under it is in the tree at
    /// once but takes no taps until the exit animation ends.
    func tapWhenHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(eventually(5) { element.exists && element.isHittable }, "\(element) takes taps", file: file, line: line)
        element.tap()
    }

    /// The title of a row in a Library list: its label is the title and its value the status
    /// (which other texts with the same title, such as the Now Playing bar's, don't have).
    func libraryRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells.staticTexts.matching(NSPredicate(format: "label == %@ AND value LIKE '?*'", title)).firstMatch
    }

    /// The cell holding the row titled `title`.
    func libraryCell(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "elementType == %d AND label == %@ AND value LIKE '?*'",
                                         XCUIElement.ElementType.staticText.rawValue, title)).firstMatch
    }
}

extension XCUIApplication {
    /// The Library home. It has no navigation bar, so it is found by its list.
    var libraryHome: XCUIElement {
        descendants(matching: .any).matching(identifier: "libraryHome").firstMatch
    }
}
