import XCTest

/// How a UI test launches the app. Every launch starts as a fresh install would
/// (`-resetLibrary`: an empty library, the stored settings cleared), with the test markers on
/// (`-uiTesting`) and the Apple voice at 1×, then adds `arguments`: the seeds, which add to the
/// empty library, and the other options (`App/LaunchOptions.swift`).
struct UITestSetup: ExpressibleByArrayLiteral {
    var arguments: [String]
    /// The engine selected at launch (`apple`, `test.voice`, `local.kokoro`).
    var engine: String
    /// The listen speed (`-reader.rateMultiplier`); nil is 1×.
    var rate: Double?
    /// false: the library and settings the last launch left stay (a relaunch).
    var resetsLibrary: Bool
    /// true: no `-uiTesting`, so live Google suggestions, as a normal launch has them (a
    /// screenshot run that shows them).
    var usesNetwork: Bool

    init(_ arguments: [String] = [], engine: String = "apple", rate: Double? = nil, resetsLibrary: Bool = true,
         usesNetwork: Bool = false) {
        self.arguments = arguments
        self.engine = engine
        self.rate = rate
        self.resetsLibrary = resetsLibrary
        self.usesNetwork = usesNetwork
    }

    init(arrayLiteral arguments: String...) { self.init(arguments) }

    /// The same launch again, keeping what this one leaves.
    static func relaunch(_ arguments: [String] = []) -> UITestSetup { UITestSetup(arguments, resetsLibrary: false) }

    var launchArguments: [String] {
        (usesNetwork ? [] : ["-uiTesting"]) + (resetsLibrary ? ["-resetLibrary"] : []) + ["-selectEngine", engine]
            + (rate.map { ["-reader.rateMultiplier", "\($0)"] } ?? []) + arguments
    }
}

extension XCUIElement {
    /// Whether the element holds the keyboard focus: an attribute XCUIElement has but doesn't
    /// declare.
    var hasKeyboardFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }
}

/// Launches, waits and lookups shared by the UI tests.
extension XCTestCase {
    /// The one way a UI test launches the app (`UITestSetup`).
    @discardableResult
    func launch(_ setup: UITestSetup = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = setup.launchArguments
        app.launch()
        return app
    }

    /// The demo article, 40 paragraphs long, in the Library.
    func launchLongDemo(_ extra: [String] = []) -> XCUIApplication {
        launch(UITestSetup(["-seedDemoArticle", "-seedDemoParagraphs", "40", "-openLibrary"] + extra))
    }

    /// The long demo article's text is laid out on the reading page, so a drag really scrolls it.
    func waitForLongDemoText(_ app: XCUIApplication) {
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Extra paragraph 12'")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15), "article text loaded")
        idle(0.5)
    }

    func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func idle(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    /// Taps the dimmed area around an open ⋯ panel near the top of the screen: its middle can be
    /// under a tall panel, where the tap would land on a row.
    func tapMenuDim(_ dismiss: XCUIElement) {
        dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }

    /// Closes the open ⋯ panel by its dimmed area and waits until it has gone.
    func closeMenu(_ app: XCUIApplication) {
        let dim = find(app, "moreMenuDismiss")
        XCTAssertTrue(dim.waitForExistence(timeout: 3), "the ⋯ panel is open")
        tapMenuDim(dim)
        waitForMenuToClose(app)
    }

    /// Waits until the ⋯ panel has gone, collapsing included: it is modal, and until it has gone
    /// it takes the taps meant for what is under it.
    func waitForMenuToClose(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(eventually(5) { !self.find(app, "moreMenuPanel").exists && !self.find(app, "moreMenuDismiss").exists },
                      "the ⋯ panel closed", file: file, line: line)
    }

    func eventually(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            idle(0.1)
        }
        return condition()
    }

    /// The frames of `elements` once they read the same twice in a row, 0.2 s apart: a sheet has
    /// finished rising, a panel growing, a list settling. Nil if they don't settle in `timeout`.
    func settledFrames(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> [CGRect]? {
        var last = elements.map(\.frame)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            idle(0.2)
            let now = elements.map(\.frame)
            if now == last, now.allSatisfy({ !$0.isEmpty }) { return now }
            last = now
        }
        return nil
    }

    /// The offline test pages, on page one.
    func launchTestPages(_ extra: [String] = []) -> XCUIApplication {
        launch(UITestSetup(["-browseTestPages"] + extra))
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

    /// What Now Playing's close pill says it plays from ("Playing from Library").
    func playingFrom(_ app: XCUIApplication) -> String? {
        app.buttons["nowPlayingClose"].value as? String
    }

    /// Settings is open: scrolls its list until the row `id` can be tapped, and taps it.
    func openSettingsRow(_ app: XCUIApplication, _ id: String) {
        let row = find(app, id)
        let list = find(app, "settingsList")
        for _ in 0..<10 where !(row.exists && row.isHittable) { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable, "Settings row \(id)")
        row.tap()
    }

    /// Pulls a sheet down by its header (the element `id` sits in it), between the close pill and
    /// Aa.
    func pullDown(_ app: XCUIApplication, from id: String) {
        let start = find(app, id).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 60, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 420)),
                    withVelocity: .default, thenHoldForDuration: 0)
    }
}
