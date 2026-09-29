import XCTest
@testable import Reader

final class ContinueListeningTests: XCTestCase {
    private func c(_ id: UUID = UUID(), saved: TimeInterval = 0, p: Int = 0, off: Int = 0, n: Int? = 10) -> ContinueListening.Candidate {
        .init(id: id, savedAt: Date(timeIntervalSince1970: saved), paragraph: p, utf16Offset: off, paragraphCount: n)
    }

    func testUnstartedArticlesAreNotInProgress() {
        XCTAssertTrue(ContinueListening.inProgress([c(), c(saved: 5)], history: .init()).isEmpty)
    }

    func testLegacyProgressCountsUnlessParkedAtTheEnd() {
        let mid = c(p: 3), end = c(p: 9, n: 10), unknown = c(p: 2, n: nil)
        let ids = ContinueListening.inProgress([mid, end, unknown], history: .init()).map(\.id)
        XCTAssertEqual(Set(ids), [mid.id, unknown.id])
    }

    func testHistoryOrdersByMostRecentListenAndFinishedDropsOut() {
        let a = c(saved: 30, p: 1), b = c(saved: 20), d = c(saved: 10, p: 4)
        var h = ListenHistory()
        h.touch(b.id, at: Date(timeIntervalSince1970: 200)) // listened at paragraph 0 still counts
        h.touch(d.id, at: Date(timeIntervalSince1970: 100))
        h.markFinished(a.id, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(ContinueListening.inProgress([a, b, d], history: h).map(\.id), [b.id, d.id])
        h.touch(a.id, at: Date(timeIntervalSince1970: 400)) // re-listen: back in progress, first
        XCTAssertEqual(ContinueListening.inProgress([a, b, d], history: h).map(\.id), [a.id, b.id, d.id])
    }

    func testHistoryPersistsAndIsCapped() {
        let suite = "ContinueListeningTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID()
        ListenHistory.record(first, defaults: defaults)
        XCTAssertEqual(ListenHistory(defaults: defaults).entry(for: first)?.done, false)
        var h = ListenHistory(defaults: defaults)
        h.touch(first, at: Date(timeIntervalSince1970: 1)) // make it the oldest
        for i in 0..<(ListenHistory.maxEntries + 5) {
            h.touch(UUID(), at: Date(timeIntervalSince1970: Double(1_000_000 + i)))
        }
        h.save(to: defaults)
        let loaded = ListenHistory(defaults: defaults)
        XCTAssertEqual(loaded.entries.count, ListenHistory.maxEntries)
        XCTAssertNil(loaded.entry(for: first), "oldest entry is dropped")
    }
}
