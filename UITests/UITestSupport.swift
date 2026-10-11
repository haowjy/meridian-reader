import XCTest

/// Small waits and lookups shared by the two-states UI tests.
extension XCTestCase {
    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func idle(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    /// Taps the dimmed area around an open ⋯ panel near the top of the screen: its middle can be
    /// under a tall panel, where the tap would land on a row.
    func tapMenuDim(_ dismiss: XCUIElement) {
        dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            idle(0.1)
        }
        return condition()
    }

    /// The offline test pages, Apple voice at 1×, no bookmarks.
    func launchTestPages(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-browseTestPages", "-resetBookmarks", "-selectEngine", "apple",
                               "-reader.rateMultiplier", "1"] + extra
        app.launch()
        return app
    }

    /// From test page one, follow the link `title` and wait for its 🎧 (or, for page one, its links).
    func openTestPage(_ app: XCUIApplication, _ link: String) {
        let anchor = app.links[link]
        XCTAssertTrue(anchor.waitForExistence(timeout: 10), "link \(link)")
        anchor.tap()
        XCTAssertTrue(find(app, "addressListen").waitForExistence(timeout: 10), "🎧 on \(link)")
    }

    /// ‹ back to test page one.
    func backToPageOne(_ app: XCUIApplication) {
        app.buttons["browseBack"].tap()
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10), "page one")
    }

    /// 🎧 on the page shown, then wait until it is what you hear.
    func listenHere(_ app: XCUIApplication) {
        let listen = find(app, "addressListen")
        XCTAssertTrue(listen.waitForExistence(timeout: 5))
        listen.tap()
        XCTAssertTrue(eventually(10) { listen.label == "Pause" }, "🎧 playing, got \(listen.label)")
    }

    /// Pulls a sheet down by its header (the element `id` sits in it).
    func pullDown(_ app: XCUIApplication, from id: String) {
        let start = find(app, id).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 120, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)),
                    withVelocity: .default, thenHoldForDuration: 0)
    }
}
