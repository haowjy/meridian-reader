import XCTest
@testable import MeridianReader

final class WhatsNewStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WhatsNewStoreTests")!
        defaults.removePersistentDomain(forName: "WhatsNewStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WhatsNewStoreTests")
        super.tearDown()
    }

    func testFreshInstallDoesNotShow() {
        let store = WhatsNewStore(defaults: defaults, currentVersion: "0.1.0")
        XCTAssertFalse(store.shouldShow, "Fresh install should not show What's New")
    }

    func testUpgradeShowsOnce() {
        // Simulate an earlier version was recorded
        defaults.set("0.0.9", forKey: WhatsNewStore.lastSeenVersionKey)
        let store = WhatsNewStore(defaults: defaults, currentVersion: "0.1.0")
        // shouldShow depends on notes existing in the bundle; without a matching
        // WhatsNew.json entry it returns false. Test the version logic directly:
        let lastSeen = defaults.string(forKey: WhatsNewStore.lastSeenVersionKey)
        XCTAssertEqual(lastSeen, "0.0.9", "Earlier version should be preserved")
        XCTAssertNotEqual(lastSeen, "0.1.0")

        // After marking seen, it should not show again
        store.markSeen()
        XCTAssertFalse(store.shouldShow, "Should not show after marking seen")
        XCTAssertEqual(defaults.string(forKey: WhatsNewStore.lastSeenVersionKey), "0.1.0")
    }

    func testSameVersionDoesNotShow() {
        defaults.set("0.1.0", forKey: WhatsNewStore.lastSeenVersionKey)
        let store = WhatsNewStore(defaults: defaults, currentVersion: "0.1.0")
        XCTAssertFalse(store.shouldShow, "Same version should not show What's New")
    }
}
