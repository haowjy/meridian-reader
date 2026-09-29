import Foundation

/// When each article was last listened to, and whether it was listened to the end. Drives the
/// start page's "Continue listening" order. Kept in UserDefaults (not the SwiftData row) so no
/// schema change; capped, oldest dropped.
struct ListenHistory: Equatable {
    struct Entry: Codable, Equatable {
        var at: Double
        var done: Bool
    }

    static let storageKey = "reader.listenHistory.v1"
    static let maxEntries = 80

    private(set) var entries: [String: Entry]

    init(entries: [String: Entry] = [:]) { self.entries = entries }

    init(defaults: UserDefaults) {
        let data = defaults.data(forKey: Self.storageKey)
        entries = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.storageKey)
    }

    func entry(for id: UUID) -> Entry? { entries[id.uuidString] }

    /// Listening happened now (clears `done`: re-listening puts it back in progress).
    mutating func touch(_ id: UUID, at date: Date = .now) {
        entries[id.uuidString] = Entry(at: date.timeIntervalSince1970, done: false)
        trim()
    }

    /// Played to the end: drops out of Continue listening.
    mutating func markFinished(_ id: UUID, at date: Date = .now) {
        entries[id.uuidString] = Entry(at: date.timeIntervalSince1970, done: true)
        trim()
    }

    private mutating func trim() {
        guard entries.count > Self.maxEntries else { return }
        let keep = entries.sorted { $0.value.at > $1.value.at }.prefix(Self.maxEntries)
        entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    /// Convenience for call sites that just record one event.
    static func record(_ id: UUID, finished: Bool = false, defaults: UserDefaults = .standard) {
        var h = ListenHistory(defaults: defaults)
        if finished { h.markFinished(id) } else { h.touch(id) }
        h.save(to: defaults)
    }
}

/// Which saved articles are "in progress", most recently listened first.
enum ContinueListening {
    struct Candidate: Equatable {
        let id: UUID
        let savedAt: Date
        let paragraph: Int
        let utf16Offset: Int
        /// nil when the listen blocks haven't been built yet.
        let paragraphCount: Int?
    }

    /// In progress = listened to (history entry, not finished) or, for saves that predate the
    /// history, a playhead past the start that isn't parked on the last paragraph.
    static func inProgress(_ candidates: [Candidate], history: ListenHistory) -> [Candidate] {
        let picked = candidates.filter { c in
            if let e = history.entry(for: c.id) { return !e.done }
            guard c.paragraph > 0 || c.utf16Offset > 0 else { return false }
            if let n = c.paragraphCount, n > 1, c.paragraph >= n - 1 { return false }
            return true
        }
        return picked.sorted { a, b in
            let ta = history.entry(for: a.id)?.at
            let tb = history.entry(for: b.id)?.at
            switch (ta, tb) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.savedAt > b.savedAt
            }
        }
    }
}
