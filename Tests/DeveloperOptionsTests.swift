import XCTest
@testable import Reader

/// Developer options (Debug rows, Listen debug): on by default in Debug builds, off in Release,
/// and a stored unlock from an older build is cleared once on Release.
final class DeveloperOptionsTests: XCTestCase {
    func testReleaseResetClearsStoredDeveloperOptionsOnce() {
        let name = "DeveloperOptionsTests.\(UUID().uuidString)"
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
        let name = "DeveloperOptionsTests.debug.\(UUID().uuidString)"
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
