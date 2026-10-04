import XCTest

/// The screenshot that started the redesign: what you hear and what you see are two things. The
/// Now Playing bar always shows what you hear; each page's 🎧 says whether it is that page.
/// Offline test pages, Apple voice.
final class TwoStatesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPlayingPageAndBrowsedPageReadAsTwoThings() throws {
        let app = launchTestPages()
        let bar = find(app, "nowPlayingBarOpen")
        let listen = find(app, "addressListen")

        // Page one isn't readable: no 🎧, and nothing has played: no bar.
        XCTAssertTrue(app.links["Next page"].waitForExistence(timeout: 10))
        XCTAssertFalse(listen.exists, "no 🎧 on a page that isn't readable")
        XCTAssertFalse(bar.exists, "no bar before anything has played")

        // Play page A from its 🎧.
        openTestPage(app, "Next page")
        XCTAssertEqual(listen.label, "Listen", "grey before it plays")
        listenHere(app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar shows what you hear")
        XCTAssertTrue(bar.label.contains("Second page"), bar.label)

        // Browse to page B: the bar still shows A, with its site; B's 🎧 is grey.
        backToPageOne(app)
        XCTAssertFalse(listen.exists, "page one still has no 🎧")
        openTestPage(app, "Third page")
        XCTAssertEqual(listen.label, "Listen", "B isn't what you hear")
        XCTAssertTrue(bar.label.contains("Second page"), "the bar still shows A: \(bar.label)")
        XCTAssertTrue(bar.label.contains("pages"), "with A's site: \(bar.label)")
        XCTAssertEqual(find(app, "nowPlayingBarPlayPause").label, "Pause", "A keeps playing")

        // Back on A: its 🎧 is blue (what you hear).
        backToPageOne(app)
        openTestPage(app, "Next page")
        XCTAssertEqual(listen.label, "Pause", "A is what you hear")

        // B's 🎧 replaces what you hear.
        backToPageOne(app)
        openTestPage(app, "Third page")
        listenHere(app)
        XCTAssertTrue(eventually(5) { bar.label.contains("Third page") }, "the bar shows B: \(bar.label)")

        // A readable page with too little text: the toast, and B keeps playing.
        backToPageOne(app)
        openTestPage(app, "Thin page")
        listen.tap()
        let toast = find(app, "toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "toast")
        XCTAssertTrue(toast.label.contains("Nothing to listen to on this page"), toast.label)
        XCTAssertTrue(eventually(5) { listen.label == "Listen" }, "🎧 back to grey")
        XCTAssertTrue(bar.label.contains("Third page"), "what you hear didn't change: \(bar.label)")
        XCTAssertEqual(find(app, "nowPlayingBarPlayPause").label, "Pause", "still playing")
        find(app, "nowPlayingBarPlayPause").tap()
    }
}
