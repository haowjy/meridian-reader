import Foundation

/// When each article was last listened to, and whether to the end, as the app kept it in
/// UserDefaults (`reader.listenHistory.v1`) before the library. **Frozen:** the library migration
/// folds it into `Article.lastPlayedAt` / `finishedAt`, and nothing writes it again.
struct ListenHistory: Equatable {
    struct Entry: Codable, Equatable {
        /// Seconds since 1970.
        var at: Double
        var done: Bool
    }

    static let storageKey = "reader.listenHistory.v1"

    private(set) var entries: [String: Entry]

    init(defaults: UserDefaults) {
        let data = defaults.data(forKey: Self.storageKey)
        entries = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func entry(for id: UUID) -> Entry? { entries[id.uuidString] }
}
