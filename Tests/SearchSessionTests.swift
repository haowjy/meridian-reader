import XCTest
@testable import Reader

@MainActor
final class SearchSessionTests: XCTestCase {
    func testFocusWhileIdleBeginsWithTheGivenTextUntouched() {
        let session = SearchSession()
        session.text = "example.com/post"
        session.focusChanged(true) { "https://example.com/post" }
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isFocused)
        XCTAssertEqual(session.text, "https://example.com/post")
        XCTAssertTrue(session.isUntouched, "the page address, untouched: recents show")
        session.text = "swift"
        XCTAssertFalse(session.isUntouched)
        session.text = "https://example.com/post"
        XCTAssertTrue(session.isUntouched, "typed back to the start text")
    }

    func testRefocusDuringSessionKeepsTypedText() {
        let session = SearchSession()
        session.begin()
        session.text = "zzq"
        session.lowerKeyboard()
        XCTAssertTrue(session.isActive, "swipe-down keeps the session")
        session.focusChanged(true) { "ignored" }
        XCTAssertEqual(session.text, "zzq")
    }

    func testFillIsNeverUntouchedUnlessEmpty() {
        let session = SearchSession()
        session.begin(with: "swift")
        session.fill("swift")
        XCTAssertFalse(session.isUntouched, "a filled term shows suggestions even if it equals the start")
        session.text = "  "
        XCTAssertTrue(session.isUntouched, "an empty field always shows recents")
    }

    func testEndRestoresIdleText() {
        let session = SearchSession()
        session.begin()
        session.text = "abc"
        session.end(showing: "example.com")
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isFocused)
        XCTAssertFalse(session.isUntouched)
        XCTAssertEqual(session.text, "example.com")
    }

    func testAddressText() {
        XCTAssertEqual(ShellState.addressText(for: nil), "")
        XCTAssertEqual(ShellState.addressText(for: URL(string: "https://example.com/")!), "example.com")
        XCTAssertEqual(ShellState.addressText(for: URL(string: "https://example.com/a/b?q=1")!), "example.com/a/b")
        XCTAssertEqual(ShellState.addressText(for: URL(string: "reader-test://pages/one")!), "pages/one")
    }

    func testLaunchOptions() {
        let none = LaunchOptions(arguments: ["Reader"])
        XCTAssertFalse(none.uiTesting)
        XCTAssertTrue(none.fetchesSuggestions)
        XCTAssertNil(none.demoArticle)
        XCTAssertNil(none.bookmarks)

        let ui = LaunchOptions(arguments: ["Reader", "-uiTesting", "-seedDemoArticle", "-seedDemoParagraphs", "40",
                                           "-seedDemoTitle", "Long", "-resetBookmarks", "-seedBookmarks",
                                           "-bakeArticle", "0c25b7ee", "-scrubBubbleDemo"])
        XCTAssertFalse(ui.fetchesSuggestions, "UI tests never depend on live Google suggestions")
        XCTAssertEqual(ui.demoArticle, .init(title: "Long", paragraphs: 40, progress: 0))
        XCTAssertEqual(ui.bookmarks, .seed)
        XCTAssertEqual(ui.bakeArticlePrefix, "0C25B7EE")
        XCTAssertTrue(ui.scrubBubbleDemo)
        XCTAssertEqual(LaunchOptions(arguments: ["-seedDemoArticle", "-seedDemoParagraphs", "1"]).demoArticle?.paragraphs, 3)
        XCTAssertFalse(LaunchOptions(arguments: ["-scrubBubbleDemo"]).scrubBubbleDemo, "screenshot hook needs -uiTesting")
    }

    func testUITestingLaunchSendsNoGoogleQuery() {
        let ui = LaunchOptions(arguments: ["Reader", "-uiTesting"])
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "swift", enabled: ui.fetchesSuggestions))
        let normal = LaunchOptions(arguments: ["Reader"])
        XCTAssertEqual(GoogleSuggestClient.query(forTyped: " swift ", enabled: normal.fetchesSuggestions), "swift")
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "  ", enabled: true))
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "example.com/post", enabled: true), "addresses aren't searched")
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "https://example.com", enabled: true))
        XCTAssertEqual(GoogleSuggestClient.query(forTyped: "swift 6.2 release", enabled: true), "swift 6.2 release")
    }
}
