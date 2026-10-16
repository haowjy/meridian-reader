import XCTest

/// Browse: while typing in the (bottom) address field with the keyboard up, the field must stay
/// visible — above the keyboard and below the status bar — however many suggestions there are.
final class BrowseAddressKeyboardUITests: XCTestCase {
    private func statusBarBottom() -> CGFloat {
        let bar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        if bar.exists, bar.frame.height > 0 { return bar.frame.maxY }
        return 50 // conservative fallback (status bar ≈ 54–62 pt on Face ID iPhones)
    }

    private func assertFieldVisible(_ app: XCUIApplication, _ field: XCUIElement, typed: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let top = statusBarBottom()
        XCTAssertTrue(field.isHittable, "field hittable while typing \(typed)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(field.frame.minY, top, "field below the status bar (\(field.frame))", file: file, line: line)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY,
                                     "field above the keyboard (\(field.frame) vs \(keyboard.frame))", file: file, line: line)
        }
        XCTAssertEqual(field.value as? String, typed, "typed text is in the field", file: file, line: line)
        // The landing helper text must not be pushed up under the clock.
        let helper = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Search or enter an address below")).firstMatch
        if helper.exists, helper.isHittable {
            XCTAssertGreaterThanOrEqual(helper.frame.minY, top, "nothing under the status bar", file: file, line: line)
        }
    }

    func testAddressFieldStaysVisibleAboveKeyboard() throws {
        // The seeded save (example.com) is a local suggestion; UI tests fetch none from Google.
        let app = launch(["-seedDemoArticle"])

        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "software keyboard is up")

        let suggestion = find(app, "addressEditBackdrop").staticTexts["Demo Listen Article"]
        field.typeText("e")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "the saved article is suggested")
        XCTAssertNotNil(settledFrames([field, suggestion]), "the field and its suggestions settle")
        assertFieldVisible(app, field, typed: "e")

        field.typeText("xample")
        XCTAssertTrue(eventually { field.value as? String == "example" })
        XCTAssertNotNil(settledFrames([field, suggestion]), "the field and its suggestions settle")
        assertFieldVisible(app, field, typed: "example")
    }
}
