import Foundation

/// Unofficial Google Search suggest endpoint (same shape many browsers use).
/// Not a supported Google product API — may change or block without notice.
enum GoogleSuggestClient {
    private static let session: URLSession = {
        // Nothing that identifies the user goes with the typed text: no cookies in or out, no cache,
        // no credentials, no Referer (a bare URLSession sends none).
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// What to ask Google for text typed in the address field, or nil: suggestions are off
    /// (`enabled` false, e.g. `-uiTesting`), nothing is typed, or Submit would load the text as an
    /// address (`BrowseURLParser`).
    static func query(forTyped text: String, enabled: Bool) -> String? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, BrowseURLParser.isSearch(q) else { return nil }
        return q
    }

    /// The suggestions in a response body: `["query", ["sugg1", "sugg2", ...]]`, trimmed, each once
    /// (case-insensitive), at most `limit`. `[]` for anything else.
    static func parse(_ data: Data, limit: Int) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count >= 2, let list = root[1] as? [String] else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for item in list {
            let s = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, seen.insert(s.lowercased()).inserted else { continue }
            out.append(s)
            if out.count >= limit { break }
        }
        return out
    }

    /// Returns up to `limit` suggestion strings for `query`, or `[]` on any failure.
    static func suggestions(for query: String, limit: Int = SearchSuggestions.maxRows) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components?.url else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return parse(data, limit: limit)
        } catch {
            return []
        }
    }
}

/// Live search suggestions in the address field. The app has one search engine (Google, in
/// `BrowseURLParser`), so one source; the typed text goes to its suggest endpoint only while
/// Settings › Search Suggestions is on, and never for text that would load as an address.
struct SearchSuggestionProvider: Sendable {
    var suggestions: @Sendable (String) async -> [String]

    /// Google's suggest endpoint.
    static let live = SearchSuggestionProvider { await GoogleSuggestClient.suggestions(for: $0) }
    /// Probes: fixed rows, so a run never reaches the network (`-stubSuggestions`).
    static let stub = SearchSuggestionProvider { ["\($0) meaning", "\($0) near me", "\($0) news"] }
    /// Nothing (an `-uiTesting` launch that doesn't ask for suggestions).
    static let none = SearchSuggestionProvider { _ in [] }
}

enum SearchSuggestions {
    /// `@AppStorage` key of the Settings switch; on unless turned off.
    static let storageKey = "browse.searchSuggestions"
    static let storedKeys = [storageKey]
    /// A pause in typing before a request goes out.
    static let debounce: Duration = .milliseconds(150)
    /// Rows the card shows under its `Search "…"` row, history and saved pages included.
    static let maxRows = 6

    /// The suggestions for `typed` once typing has paused for `debounce`. A new keystroke cancels
    /// the task running this (`.task(id:)`), which cancels the sleep and the request; a cancelled
    /// call returns `[]` so a late answer is never used. `[]` too when `enabled` is false or the text
    /// would load as an address, with no request and no wait.
    static func rows(typed: String, enabled: Bool, provider: SearchSuggestionProvider,
                     debounce: Duration = debounce) async -> [String] {
        guard let q = GoogleSuggestClient.query(forTyped: typed, enabled: enabled) else { return [] }
        do { try await Task.sleep(for: debounce) } catch { return [] }
        let rows = await provider.suggestions(q)
        return Task.isCancelled ? [] : Array(rows.prefix(maxRows))
    }
}
