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
        let provider = BundledRuleList(store: try XCTUnwrap(WKContentRuleListStore(url: dir)))

        let compiled: [String] = try await provider.ruleLists().map { $0.identifier }
        let lookedUp: [String] = try await provider.ruleLists().map { $0.identifier }
        XCTAssertEqual(compiled.count, 1)
        XCTAssertEqual(compiled, lookedUp)
        let identifiers = await provider.store.availableIdentifiers()
        XCTAssertEqual(identifiers, compiled)
    }
}
