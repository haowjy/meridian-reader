import XCTest
@testable import Reader

/// Now Playing opens at the Reader's offset (D2) once the page's layout can hold it. The offset
/// belongs to one load; a scrub, follow, drag or new load drops it; and it never waits for ever: an
/// offset the page can't reach is clamped once layout settles.
@MainActor
final class ReadingScrollRestoreTests: XCTestCase {
    // MARK: The decision

    private let restore = ReadingScrollRestore(offset: 900, generation: 1)
    private typealias Layout = ReadingScrollRestore.Layout

    func testAReachableOffsetIsSetAsSoonAsLayoutHoldsIt() {
        let layout = Layout(contentHeight: 3000, viewportHeight: 600, insetTop: 50, insetBottom: 100)
        XCTAssertEqual(restore.step(in: layout, quiet: false, expired: false), .scroll(to: 900))
    }

    func testBeforeLayoutItWaitsUntilTheWaitRunsOut() {
        let none = Layout(contentHeight: 0, viewportHeight: 600, insetTop: 50)
        XCTAssertEqual(restore.step(in: none, quiet: true, expired: false), .wait, "a still, empty page isn't laid out")
        XCTAssertEqual(restore.step(in: none, quiet: false, expired: true), .scroll(to: -50), "out of time: the top")
        let noViewport = Layout(contentHeight: 3000, viewportHeight: 0)
        XCTAssertEqual(restore.step(in: noViewport, quiet: true, expired: false), .wait)
    }

    func testAnOffsetThePageCantReachWaitsForLayoutToSettleThenClamps() {
        let short = Layout(contentHeight: 1000, viewportHeight: 600, insetTop: 50, insetBottom: 100)
        XCTAssertEqual(restore.step(in: short, quiet: false, expired: false), .wait, "layout may still grow")
        XCTAssertEqual(restore.step(in: short, quiet: true, expired: false), .scroll(to: 500), "settled: the end")
        XCTAssertEqual(restore.step(in: short, quiet: false, expired: true), .scroll(to: 500), "out of time: the end")
        let above = ReadingScrollRestore(offset: -400, generation: 1)
        XCTAssertEqual(above.step(in: short, quiet: true, expired: false), .scroll(to: -50), "above the top: the top")
    }

    func testViewportAndInsetsDecideWhatIsReachable() {
        let tall = Layout(contentHeight: 1400, viewportHeight: 600)
        XCTAssertEqual(restore.step(in: tall, quiet: false, expired: false), .wait, "800 is the end")
        XCTAssertEqual(restore.step(in: Layout(contentHeight: 1400, viewportHeight: 500), quiet: false, expired: false),
                       .scroll(to: 900), "a shorter viewport reaches it")
        XCTAssertEqual(restore.step(in: Layout(contentHeight: 1400, viewportHeight: 600, insetBottom: 120),
                                    quiet: false, expired: false),
                       .scroll(to: 900), "so does room left below the text")
    }

    // MARK: On the reading page

    private var page: ReadingPageHarness!

    override func setUp() async throws {
        page = ReadingPageHarness()
    }

    override func tearDown() async throws {
        page.close()
        page = nil
    }

    func testOpensAtTheHandedOverOffset() async throws {
        try await page.load(ReadingPageHarness.paragraphs(40), blocks: 40, opensAt: 1200)
        try await page.waitUntil("restored", timeout: 3) { !self.page.coordinator.isRestoringScroll }
        XCTAssertEqual(page.offset, 1200, accuracy: 1)
    }

    /// Past the end of the page: once layout settles the text opens at the end, and the restore is
    /// over, so a page that grows later doesn't jump back to the old offset.
    func testAnOffsetPastTheEndClampsToTheEndAndFinishes() async throws {
        page.coordinator.restoreTiming = (quiet: 0.3, limit: 2)
        try await page.load(ReadingPageHarness.paragraphs(8), blocks: 8, opensAt: 5000)
        let start = Date()
        try await page.waitUntil("restore finished", timeout: 3) { !self.page.coordinator.isRestoringScroll }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.5, "bounded wait")
        let end = page.maxOffset
        XCTAssertGreaterThan(end, 0, "the page is taller than its viewport")
        XCTAssertLessThan(end, 5000)
        XCTAssertEqual(page.offset, end, accuracy: 1, "clamped to the end")

        try await grow(by: 60, after: 8)
        XCTAssertGreaterThan(page.maxOffset, 5000, "5000 is reachable now")
        XCTAssertEqual(page.offset, end, accuracy: 1, "the finished restore doesn't come back")
    }

    /// A scrub while the restore waits: the scrub wins, and a later layout doesn't undo it.
    func testAScrubBeforeTheRestoreWins() async throws {
        page.coordinator.restoreTiming = (quiet: 30, limit: 60) // keeps it waiting
        try await page.load(ReadingPageHarness.paragraphs(8), blocks: 8, opensAt: 5000)
        try await page.pause(0.3)
        XCTAssertTrue(page.coordinator.isRestoringScroll, "5000 is past the end: still waiting")

        page.coordinator.scroll(ReaderScrollRequest(index: 2, token: 1))
        XCTAssertFalse(page.coordinator.isRestoringScroll, "the scrub drops it")
        try await page.pause(0.3)
        let scrubbed = page.offset

        try await grow(by: 60, after: 8)
        XCTAssertGreaterThan(page.maxOffset, 5000)
        XCTAssertEqual(page.offset, scrubbed, accuracy: 1, "still where the scrub put it, not at 5000")
    }

    /// A scrub while the page is still loading, before the restore has started: the scrub wins,
    /// once the page can scroll, and the handed-over offset is never applied.
    func testAScrubBeforeThePageFinishesLoadingWins() async throws {
        page.coordinator.load(html: ReadingPageHarness.paragraphs(40), opensAt: 3000)
        page.coordinator.scroll(ReaderScrollRequest(index: 1, token: 1))
        try await page.waitUntil("page loaded and indexed") {
            guard !self.page.webView.isLoading else { return false }
            return (try await self.page.js("document.querySelectorAll('[data-reader-index]').length") as? Int) == 40
        }
        try await page.pause(0.5)
        XCTAssertFalse(page.coordinator.isRestoringScroll, "the scrub dropped the queued restore")
        XCTAssertLessThan(page.offset, 1000, "near the second paragraph, not at the handed-over 3000")
        XCTAssertGreaterThan(page.maxOffset, 3000, "3000 was reachable, so only the scrub kept it away")
    }

    /// A new page while the restore waits: it opens at its top; the old offset was for the old page.
    func testAReloadBeforeTheRestoreOpensTheNewPageAtTheTop() async throws {
        page.coordinator.restoreTiming = (quiet: 30, limit: 60)
        try await page.load(ReadingPageHarness.paragraphs(8), blocks: 8, opensAt: 5000)
        try await page.pause(0.3)
        XCTAssertTrue(page.coordinator.isRestoringScroll)

        try await page.load(ReadingPageHarness.paragraphs(70), blocks: 70)
        XCTAssertFalse(page.coordinator.isRestoringScroll, "the new load drops it")
        try await page.waitUntil("laid out", timeout: 3) { self.page.maxOffset > 5000 }
        try await page.pause(0.5)
        XCTAssertEqual(page.offset, -page.scrollView.contentInset.top, accuracy: 1, "the new page's top")
    }

    /// Appends paragraphs and waits for the scroll view to see them.
    private func grow(by count: Int, after existing: Int) async throws {
        let html = ReadingPageHarness.paragraphs(count, from: existing + 1).replacingOccurrences(of: "\n", with: "")
        let before = page.scrollView.contentSize.height
        _ = try await page.js("document.body.insertAdjacentHTML('beforeend', '\(html)'); true")
        try await page.waitUntil("taller", timeout: 3) { self.page.scrollView.contentSize.height > before + 1000 }
        try await page.pause(0.5) // any layout callbacks have run
    }
}
