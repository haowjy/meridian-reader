import Foundation

/// Unofficial Google Search suggest endpoint (same shape many browsers use).
/// Not a supported Google product API — may change or block without notice.
enum GoogleSuggestClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        return URLSession(configuration: config)
    }()

    /// What to ask Google for text typed in the address field, or nil: suggestions are off
    /// (`enabled` false, e.g. UI tests), nothing is typed, or the text looks like an address.
    static func query(forTyped text: String, enabled: Bool) -> String? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !q.isEmpty else { return nil }
        let looksLikeAddress = q.contains("://") || (q.contains(".") && !q.contains(" ") && q.count > 4)
        return looksLikeAddress ? nil : q
    }

    /// Returns up to `limit` suggestion strings for `query`, or `[]` on any failure.
    static func suggestions(for query: String, limit: Int = 8) async -> [String] {
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
            // Payload: ["query", ["sugg1", "sugg2", ...]]
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [Any],
                root.count >= 2,
                let list = root[1] as? [String]
            else {
                return []
            }
            var seen = Set<String>()
            var out: [String] = []
            for item in list {
                let s = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { continue }
                let key = s.lowercased()
                guard seen.insert(key).inserted else { continue }
                out.append(s)
                if out.count >= limit { break }
            }
            return out
        } catch {
            return []
        }
    }
}
