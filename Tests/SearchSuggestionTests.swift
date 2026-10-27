import XCTest
@testable import MeridianReader

/// Live search suggestions: reading the engine's answer, deciding what is worth asking about, the
/// debounce and the stale-answer rule, and how the answer joins history and saved pages in the card.
final class SearchSuggestionTests: XCTestCase {
    // MARK: Parsing (Google's suggest shape: `["query", ["a", "b"], ...]`)

    func testParsesGoogleSuggestJSON() {
        let json = Data(#"["swift", ["swift ui", "swift tutorial", "swift taylor", "swift code"], [], {"google:suggesttype": []}]"#.utf8)
        XCTAssertEqual(GoogleSuggestClient.parse(json, limit: 6), ["swift ui", "swift tutorial", "swift taylor", "swift code"])
    }

    func testParsingTrimsDropsEmptiesAndRepeatsAndStopsAtTheLimit() {
        let json = Data(#"["q", ["  one ", "", "ONE", "two", "three", "four"]]"#.utf8)
        XCTAssertEqual(GoogleSuggestClient.parse(json, limit: 3), ["one", "two", "three"])
    }

    func testParsingAnythingElseIsEmpty() {
        for body in ["", "not json", "{}", "[]", #"["q"]"#, #"["q", "x"]"#, #"["q", [1, 2]]"#] {
            XCTAssertEqual(GoogleSuggestClient.parse(Data(body.utf8), limit: 6), [], body)
        }
    }

    // MARK: What is asked

    func testAskedOnlyForSearchesWhenOn() {
        XCTAssertEqual(GoogleSuggestClient.query(forTyped: "  swift ui ", enabled: true), "swift ui")
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "swift ui", enabled: false), "off in Settings")
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "   ", enabled: true))
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "https://example.com/a", enabled: true), "a URL is not a query")
        XCTAssertNil(GoogleSuggestClient.query(forTyped: "example.com", enabled: true))
    }

    // MARK: Debounce, cancel, stale

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        func record(_ q: String) { lock.lock(); asked.append(q); lock.unlock() }
        var queries: [String] { lock.lock(); defer { lock.unlock() }; return asked }
    }

    func testNothingIsRequestedWhenOffOrForAnAddress() async {
        let recorder = Recorder()
        let provider = SearchSuggestionProvider { recorder.record($0); return ["x"] }
        let off = await SearchSuggestions.rows(typed: "swift", enabled: false, provider: provider, debounce: .milliseconds(1))
        let url = await SearchSuggestions.rows(typed: "https://example.com", enabled: true, provider: provider, debounce: .milliseconds(1))
        XCTAssertEqual(off, [])
        XCTAssertEqual(url, [])
        XCTAssertEqual(recorder.queries, [])
    }

    func testAnswerIsCappedAtSixRows() async {
        let provider = SearchSuggestionProvider { _ in (1...10).map { "row \($0)" } }
        let rows = await SearchSuggestions.rows(typed: "row", enabled: true, provider: provider, debounce: .milliseconds(1))
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.first, "row 1")
    }

    /// A keystroke inside the pause cancels the earlier call before it asks: only the last text is sent.
    func testTypingInsideTheDebounceSendsOnlyTheLastText() async {
        let recorder = Recorder()
        let provider = SearchSuggestionProvider { recorder.record($0); return [$0 + "!"] }
        let pause = Duration.milliseconds(120)
        let first = Task { await SearchSuggestions.rows(typed: "s", enabled: true, provider: provider, debounce: pause) }
        try? await Task.sleep(for: .milliseconds(30))
        first.cancel()
        let second = Task { await SearchSuggestions.rows(typed: "sw", enabled: true, provider: provider, debounce: pause) }
        let a = await first.value, b = await second.value
        XCTAssertEqual(a, [])
        XCTAssertEqual(b, ["sw!"])
        XCTAssertEqual(recorder.queries, ["sw"])
    }

    /// An answer that arrives after a newer keystroke cancelled the call is dropped.
    func testALateAnswerToACancelledCallIsIgnored() async {
        let started = expectation(description: "request started")
        let provider = SearchSuggestionProvider { _ in
            started.fulfill()
            try? await Task.sleep(for: .milliseconds(150))
            return ["late"]
        }
        let task = Task { await SearchSuggestions.rows(typed: "swift", enabled: true, provider: provider, debounce: .milliseconds(1)) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        let rows = await task.value
        XCTAssertEqual(rows, [], "stale")
    }

    func testStubAndNoneProviders() async {
        let stub = await SearchSuggestionProvider.stub.suggestions("abc")
        XCTAssertEqual(stub, ["abc meaning", "abc near me", "abc news"])
        let none = await SearchSuggestionProvider.none.suggestions("abc")
        XCTAssertEqual(none, [])
    }

    // MARK: The card's rows

    private struct Page: AddressSuggestionSource {
        let id = UUID()
        var lineOne: String
        var suggestionHost: String
        var urlString: String
        var faviconData: Data? { nil }
    }

    func testLiveRowsFollowHistoryAndSavedAndNeverRepeatWhatIsTyped() {
        let visits = (1...4).map { Page(lineOne: "Swift \($0)", suggestionHost: "swift.org", urlString: "https://swift.org/\($0)") }
        let saved = (1...3).map { Page(lineOne: "Swift saved \($0)", suggestionHost: "blog.dev", urlString: "https://blog.dev/\($0)") }
        let rows = AddressSuggestions.build(query: "swift", visits: visits, articles: saved,
                                            google: ["swift", "Swift ui", "swift ui", "swift code", "swift news", "swift tips"])
        XCTAssertLessThanOrEqual(rows.count, SearchSuggestions.maxRows)
        XCTAssertEqual(rows.map(\.kind), [.recent, .recent, .saved, .google, .google, .google])
        XCTAssertEqual(rows.filter { $0.kind == .google }.map(\.title), ["Swift ui", "swift code", "swift news"])
        XCTAssertTrue(rows.allSatisfy { $0.subtitle != "Google Search" })
    }

    func testOnlyLiveRowsWhenNothingElseMatches() {
        let rows = AddressSuggestions.build(query: "zebra", visits: [Page](), articles: [Page](),
                                            google: (1...9).map { "zebra \($0)" })
        XCTAssertEqual(rows.count, 6)
    }
}
