import WebKit
import XCTest
@testable import MeridianReader

/// One wait for one navigation, shared by the hidden page fetcher and the off-screen extraction
/// view: it gives up at its time limit and ends when the caller is cancelled.
@MainActor
final class NavigationWaitTests: XCTestCase {
    /// Only web base URLs finish loading in the off-screen view; this one never does.
    private let neverLoads = URL(string: "reader-test://pages/")!
    private let html = "<!DOCTYPE html><html><body><p>Text.</p></body></html>"

    func testAnOffscreenLoadThatNeverFinishesGivesUpAtTheTimeLimit() async {
        let view = OffscreenWebView.make()
        let started = Date()
        do {
            try await OffscreenWebView.load(view, html: html, baseURL: neverLoads, timeout: 0.5)
            XCTFail("the load never finishes")
        } catch {
            guard case .engineFailed = error as? ExtractionError else { return XCTFail("\(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertNil(view.navigationDelegate, "the view lets go of the wait")
    }

    func testCancellingTheCallerEndsAnOffscreenLoad() async {
        let view = OffscreenWebView.make()
        let load = Task { try await OffscreenWebView.load(view, html: html, baseURL: neverLoads, timeout: 60) }
        try? await Task.sleep(for: .milliseconds(300))
        load.cancel()
        let started = Date()
        let result = await load.result
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testAnOffscreenLoadFinishes() async throws {
        let view = OffscreenWebView.make()
        try await OffscreenWebView.load(view, html: html, baseURL: nil, timeout: 20)
        let text = try await view.evaluateJavaScript("document.body.textContent") as? String
        XCTAssertEqual(text, "Text.")
    }

    func testCancellingTheCallerEndsAHiddenFetch() async {
        let fetcher = URLPageFetcher(timeout: 60)
        let fetch = Task { try await fetcher.snapshot(of: TestPageSchemeHandler.stallingPage) }
        try? await Task.sleep(for: .milliseconds(300))
        fetch.cancel()
        let started = Date()
        let result = await fetch.result
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
