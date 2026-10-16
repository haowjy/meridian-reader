import Foundation

/// Search terms typed into the Browse address field (not URLs), newest first. Stored locally as
/// one newline-joined string (`@AppStorage("browse.recentSearches")`).
enum RecentSearches {
    static let storageKey = "browse.recentSearches"
    static let maxEntries = 8

    static func decode(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func encode(_ terms: [String]) -> String {
        terms.joined(separator: "\n")
    }

    /// Moves `term` to the front (case-insensitive dedupe) and caps the list.
    static func adding(_ term: String, to terms: [String]) -> [String] {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !t.isEmpty else { return terms }
        var result = [t]
        for existing in terms where existing.caseInsensitiveCompare(t) != .orderedSame {
            result.append(existing)
            if result.count >= maxEntries { break }
        }
        return result
    }
}
