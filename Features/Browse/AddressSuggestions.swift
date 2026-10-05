import Foundation

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

/// A page the address field can suggest: a history visit or a saved page.
protocol AddressSuggestionSource {
    var id: UUID { get }
    var title: String { get }
    var suggestionHost: String { get }
    var urlString: String { get }
    /// Read only for rows that match (it is external storage on the SwiftData models).
    var faviconData: Data? { get }
}

extension RecentVisit: AddressSuggestionSource {
    var suggestionHost: String { host }
}

/// A saved page as a suggestion. Wraps the model (rather than conforming it) because a model's
/// `id` is its persistent identifier; the icon is read only for rows that match.
struct SavedPageSuggestion: AddressSuggestionSource {
    let page: Page

    var id: UUID { page.listenKey }
    var title: String { page.title }
    var suggestionHost: String { page.byline }
    var urlString: String { page.urlString ?? "" }
    var faviconData: Data? { page.artworkData }
}

/// What the address field suggests for typed text: matching history first, then saved articles,
/// then Google's suggestions; each URL or term once (case-insensitive).
enum AddressSuggestions {
    static let maxVisits = 4
    static let maxSaved = 3
    static let maxRows = 10

    static func build<Visits: Sequence, Articles: Sequence>(
        query: String, visits: Visits, articles: Articles, google: [String]
    ) -> [AddressSuggestion] where Visits.Element: AddressSuggestionSource, Articles.Element: AddressSuggestionSource {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var rows: [AddressSuggestion] = []
        var seen = Set<String>()
        func isNew(_ key: String) -> Bool { seen.insert(key.lowercased()).inserted }
        func matches(_ page: some AddressSuggestionSource) -> Bool {
            "\(page.title) \(page.suggestionHost) \(page.urlString)".lowercased().contains(q)
        }
        func row(_ page: some AddressSuggestionSource, prefix: String, kind: AddressSuggestion.Kind) -> AddressSuggestion {
            AddressSuggestion(id: "\(prefix)-\(page.id.uuidString)", title: page.title, subtitle: page.suggestionHost,
                              faviconData: page.faviconData, host: page.suggestionHost, query: page.urlString, kind: kind)
        }

        for visit in visits where matches(visit) && isNew(visit.urlString) {
            rows.append(row(visit, prefix: "recent", kind: .recent))
            if rows.count >= maxVisits { break }
        }

        var saved = 0
        for article in articles where matches(article) && isNew(article.urlString) {
            rows.append(row(article, prefix: "saved", kind: .saved))
            saved += 1
            if saved >= maxSaved { break }
        }

        for text in google where isNew(text) {
            rows.append(AddressSuggestion(id: "google-\(text)", title: text, subtitle: "Google Search",
                                          faviconData: nil, host: "", query: text, kind: .google))
            if rows.count >= maxRows { break }
        }
        return rows
    }
}
