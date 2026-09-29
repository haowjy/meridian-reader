import XCTest

final class UIHierarchySnapshotTests: XCTestCase {
    func testCaptureArticleListenHierarchy() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoArticle", "-uiTesting", "-openLibrary"]
        app.launch()

        let demo = app.cells.staticTexts["Demo Listen Article"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.tap()

        let play = app.buttons["listenPlayPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        let dir = URL(fileURLWithPath: "/Users/jimmyyao/Developer/Reader/.probe")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shot = XCUIScreen.main.screenshot().pngRepresentation
        try shot.write(to: dir.appendingPathComponent("ui-article-listening.png"))

        // Browser start page behind the library sheet.
        app.buttons["readerClose"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        app.swipeDown(velocity: .fast)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let browse = XCUIScreen.main.screenshot().pngRepresentation
        try browse.write(to: dir.appendingPathComponent("ui-browse.png"))
    }
}
