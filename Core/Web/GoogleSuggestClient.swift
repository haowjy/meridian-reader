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

/// One row in the address-bar suggestion list.
struct AddressSuggestion: Identifiable, Equatable {
    enum Kind: Equatable {
        case recent
        case saved
        case google
    }

    let id: String
    let title: String
    let subtitle: String?
    let faviconData: Data?
    let host: String
    /// Raw text to navigate (URL or search query).
    let query: String
    let kind: Kind
}
