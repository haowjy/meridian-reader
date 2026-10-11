import UIKit
import XCTest

extension XCUIApplication {
    /// The Library home. It has no navigation bar (its title is the first thing in its list), so
    /// it is found by its list; a pushed screen covers it, and it leaves the hierarchy then.
    var libraryHome: XCUIElement {
        descendants(matching: .any).matching(identifier: "libraryHome").firstMatch
    }
}

/// Lookups shared by the Library's UI tests.
extension XCTestCase {
    /// The Library on the demo article, book and folders, the Apple voice, no favorites.
    func launchLibrary(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemoArticle", "-seedDemoBook", "-seedDemoFolders", "-resetBookmarks",
                               "-selectEngine", "apple", "-reader.rateMultiplier", "1"] + extra + ["-openLibrary"]
        app.launch()
        XCTAssertTrue(app.libraryHome.waitForExistence(timeout: 10), "the Library")
        return app
    }

    /// The title of a row in a Library list: its label is the title and its value the status
    /// (which other texts with the same title, such as the Now Playing bar's, don't have).
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

    /// Long-presses the row titled `title` until it lifts, drags it slowly to `target`, holds
    /// there, and lets go. It moves as soon as the row lifts, before its menu is fully out: a
    /// finger that waits for the menu and then moves through it picks a menu item instead (iOS's
    /// own menu). The press lands left of the row's ▶.
    func dragRow(_ app: XCUIApplication, _ title: String, to target: XCUICoordinate) {
        let row = libraryCell(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row \(title)")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 1.0)
        idle(1)
    }

    /// A point on the row titled `title`: `dy` 0.5 is its middle (a folder there takes a drop),
    /// smaller is nearer its top (a drop there goes before it).
    func rowPoint(_ app: XCUIApplication, _ title: String, dy: CGFloat = 0.5) -> XCUICoordinate {
        libraryCell(app, title).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: dy))
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
        let folder = moveTreeFolder(app, name)
        if !folder.waitForExistence(timeout: 1) {
            tree.swipeUp()
            idle(0.8)
        }
        XCTAssertTrue(folder.waitForExistence(timeout: 3), "\(name) in the Move tree")
        folder.tap()
    }

    /// *Library (no folder)* in the open Move tree.
    func pickInMoveTree(_ app: XCUIApplication, topLevel: Bool) {
        XCTAssertTrue(find(app, "moveTree").waitForExistence(timeout: 5), "the Move tree")
        let place = app.buttons["moveTopLevel"]
        XCTAssertTrue(place.waitForExistence(timeout: 3))
        place.tap()
    }

    /// The folder `name` in the open Move tree.
    func moveTreeFolder(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "moveFolder").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
}

/// Colours read off a screenshot, for claims a test can only see (a tint, dimming).
enum ScreenColor {
    /// The median colour (sRGB, 0…1 per channel) of `region` (points) of `shot`: its background,
    /// whatever text and icons sit on it.
    static func median(in shot: XCUIScreenshot, region: CGRect) -> [Double]? {
        guard let pixels = rgba(shot, region: region), !pixels.isEmpty else { return nil }
        return (0..<3).map { channel in
            let values = stride(from: channel, to: pixels.count, by: 4).map { Double(pixels[$0]) / 255 }.sorted()
            return values[values.count / 2]
        }
    }

    /// How far apart two colours are (Euclidean, 0…√3).
    static func distance(_ a: [Double], _ b: [Double]) -> Double {
        sqrt(zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +))
    }

    /// The contrast of the text in `region` against its background (`StatusBarContrast`'s
    /// reading: the region's median against its darkest or lightest 0.5%).
    static func textContrast(in shot: XCUIScreenshot, region: CGRect) -> Double? {
        StatusBarContrast.read(shot.image, region: region)?.ratio
    }

    private static func rgba(_ shot: XCUIScreenshot, region: CGRect) -> [UInt8]? {
        let image = shot.image
        guard let cg = image.cgImage else { return nil }
        let scale = image.scale
        let pixels = CGRect(x: region.minX * scale, y: region.minY * scale,
                            width: region.width * scale, height: region.height * scale).integral
        guard let crop = cg.cropping(to: pixels) else { return nil }
        let (w, h) = (crop.width, crop.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? bytes : nil
    }
}
