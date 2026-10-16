import SwiftData
import XCTest
@testable import MeridianReader

/// History: one visit per page by its canonical URL, the newest `maxEntries`, stored through the
/// library's `commit`.
@MainActor
final class RecentVisitTests: XCTestCase {
    private var env: LibraryTestEnvironment!
    private var library: LibraryStore { env.library }

    override func setUp() async throws { env = try LibraryTestEnvironment() }
    override func tearDown() async throws { env.cleanUp() }

    private func visits() -> [RecentVisit] {
        (try? env.context.fetch(FetchDescriptor<RecentVisit>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]))) ?? []
    }

    private func visit(_ url: String, title: String? = nil) {
        env.now = env.now.addingTimeInterval(60)
        library.recordVisit(url: URL(string: url)!, title: title, faviconData: nil)
    }

    func testATrackingVariantIsTheSameVisit() {
        visit("https://example.com/story", title: "Story")
        visit("https://Example.com/story?utm_source=feed#top", title: "Story, again")
        XCTAssertEqual(visits().map(\.urlString), ["https://example.com/story"])
        XCTAssertEqual(visits().first?.title, "Story, again")
    }

    func testAPathThatDiffersInCaseIsAnotherVisit() {
        visit("https://example.com/Wiki/Foo")
        visit("https://example.com/wiki/foo")
        XCTAssertEqual(visits().map(\.urlString), ["https://example.com/wiki/foo", "https://example.com/Wiki/Foo"])
    }

    func testOnlyWebPagesAreVisits() {
        visit("reader-test://pages/one")
        XCTAssertTrue(visits().isEmpty)
    }

    func testTheListKeepsTheNewest() {
        for i in 0..<(RecentVisit.maxEntries + 5) { visit("https://example.com/\(i)") }
        let kept = visits()
        XCTAssertEqual(kept.count, RecentVisit.maxEntries)
        XCTAssertEqual(kept.first?.urlString, "https://example.com/\(RecentVisit.maxEntries + 4)")
        XCTAssertEqual(kept.last?.urlString, "https://example.com/5")
    }

    /// A visit is stored as every library change is: the listening progress waiting in the
    /// context is stored with it, and the store stops holding it for a later save.
    func testAVisitIsStoredThroughTheLibrarysCommit() {
        library.pendingListening[UUID()] = PendingListening(text: nil)
        visit("https://example.com/story")
        XCTAssertTrue(library.pendingListening.isEmpty)
        XCTAssertFalse(env.context.hasChanges)
    }
}
