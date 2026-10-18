import WebKit
import XCTest
@testable import MeridianReader

/// Block Ads' bundled list is valid WebKit content-blocker JSON: a rule WebKit rejects fails the
/// whole compile, and the app would then block nothing.
@MainActor
final class ContentBlockerTests: XCTestCase {
    func testTheBundledListCompilesAndIsLookedUpTheSecondTime() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: dir))

        let compiled = try await ContentBlocker.compiledList(in: store)
        let lookedUp = try await ContentBlocker.compiledList(in: store)
        XCTAssertEqual(compiled.identifier, lookedUp.identifier)
        let identifiers = await store.availableIdentifiers()
        XCTAssertEqual(identifiers, [compiled.identifier])
    }
}
