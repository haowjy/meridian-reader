import XCTest
@testable import Reader

final class NavJChromeTests: XCTestCase {
    func testFocusOffsetMatchesSafariNudge() {
        // 12 pt left, 10 pt up — deliberate, not dead-on (Nav J).
        XCTAssertEqual(MorphMenu.focusOffsetFromAnchor.width, 12)
        XCTAssertEqual(MorphMenu.focusOffsetFromAnchor.height, 10)
    }

    func testReleaseResetClearsStoredDeveloperOptionsOnce() {
        let name = "NavJChromeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: DeveloperOptions.defaultsKey)

        DeveloperOptions.clearStaleReleaseUnlockIfNeeded(defaults, isDebugBuild: false)
        XCTAssertEqual(defaults.bool(forKey: DeveloperOptions.defaultsKey), false)
        XCTAssertEqual(defaults.bool(forKey: DeveloperOptions.releaseResetKey), true)

        // Deliberate re-unlock must stick after the one-time reset.
        defaults.set(true, forKey: DeveloperOptions.defaultsKey)
        DeveloperOptions.clearStaleReleaseUnlockIfNeeded(defaults, isDebugBuild: false)
        XCTAssertEqual(defaults.bool(forKey: DeveloperOptions.defaultsKey), true)
    }

    func testReleaseResetSkippedInDebugBuilds() {
        let name = "NavJChromeTests.debug.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: DeveloperOptions.defaultsKey)
        DeveloperOptions.clearStaleReleaseUnlockIfNeeded(defaults, isDebugBuild: true)
        XCTAssertEqual(defaults.bool(forKey: DeveloperOptions.defaultsKey), true)
        XCTAssertNil(defaults.object(forKey: DeveloperOptions.releaseResetKey))
    }

    func testResolveDefaultsByBuild() {
        XCTAssertEqual(DeveloperOptions.resolve(stored: nil, isDebugBuild: false), false)
        XCTAssertEqual(DeveloperOptions.resolve(stored: nil, isDebugBuild: true), true)
        XCTAssertEqual(DeveloperOptions.resolve(stored: true, isDebugBuild: false), true)
        XCTAssertEqual(DeveloperOptions.resolve(stored: false, isDebugBuild: true), false)
    }
}
