import Foundation
import Observation
import SwiftData

/// The one entry point for library reads and writes: the folder tree, pages, saving, favorites,
/// the launch maintenance (migration, dedupe, layout, prune). One page per canonical URL,
/// app-wide; every content delete also removes the page's audio, which is why nothing else
/// deletes `Folder` or `Page` rows.
///
/// Lists in views read through `LibraryQueries` (with `@Query`); everything that changes the
/// library comes here. The one save path is `ArticleSaveCoordinator` → `save(_:in:)`.
@MainActor
@Observable
final class LibraryStore {
    /// A page not in the Library is kept this long after it was last played.
    static let unsavedKeepInterval: TimeInterval = 7 * 24 * 60 * 60

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let tts: LocalTTSCoordinator
    /// Stops playback when the page with this key is what's playing (before deleting its audio).
    @ObservationIgnored var stopPlaybackIfPlaying: (UUID) -> Void = { _ in }
    /// Dedupe merged the page with the first key into the page with the second: whatever holds
    /// the first key outside the library (the live session, the last-played record) follows.
    @ObservationIgnored var keyMerged: (UUID, UUID) -> Void = { _, _ in }
    /// Favorites whose icon `backfillFavoriteIcons` already fetched this launch.
    @ObservationIgnored var iconTried = Set<UUID>()
    /// How `commit` saves; tests make it fail.
    @ObservationIgnored var saveContext: (ModelContext) throws -> Void = { try $0.save() }
    /// Audio work planned with the changes not saved yet (`LibraryStore+AudioWork`).
    @ObservationIgnored var audioPlan = LibraryAudioWorkPlan()
    @ObservationIgnored let legacy: LegacyLibrarySources
    @ObservationIgnored let now: () -> Date

    init(context: ModelContext, tts: LocalTTSCoordinator, legacy: LegacyLibrarySources = .standard,
         now: @escaping () -> Date = Date.init) {
        self.context = context
        self.tts = tts
        self.legacy = legacy
        self.now = now
    }

    var audioCache: ArticleAudioCache { tts.audioCache }

    // MARK: - Lookups

    func page(key: UUID) -> Page? {
        try? context.fetch(LibraryQueries.page(key: key)).first
    }

    /// The page for a canonical URL, anywhere in the tree (the oldest, before dedupe).
    func page(canonicalURL: String) -> Page? {
        guard !canonicalURL.isEmpty else { return nil }
        return try? context.fetch(LibraryQueries.pages(canonicalURL: canonicalURL)).first
    }

    func page(url: URL) -> Page? {
        page(canonicalURL: ArticleIdentity.canonicalURLString(from: url))
    }

    /// A web page by its address first, then by key: legacy pages have random keys, so the
    /// address is what finds them.
    func page(key: UUID, canonicalURL: String?) -> Page? {
        canonicalURL.flatMap(page(canonicalURL:)) ?? page(key: key)
    }

    func folder(id: UUID) -> Folder? {
        try? context.fetch(LibraryQueries.folder(id: id)).first
    }

    /// The Favorites folder, made on first use. There is exactly one: dedupe merges extras.
    @discardableResult
    func favorites() -> Folder {
        if let existing = try? context.fetch(LibraryQueries.favorites).first { return existing }
        let folder = Folder(name: "", kind: .favorites, sortKey: -1)
        context.insert(folder)
        return folder
    }

    /// The top-level folders, Favorites first, then by `sortKey` (equal keys by id).
    func topLevelFolders() -> [Folder] {
        let all = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        return Self.ordered(all.filter { $0.parent == nil })
    }

    func subfolders(of folder: Folder) -> [Folder] {
        Self.ordered(folder.children ?? [])
    }

    /// A folder's pages in its sort.
    func pages(in folder: Folder) -> [Page] {
        (try? context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: folder.pageSort))) ?? []
    }

    /// A book's or series' chapters by `sortKey`, skipped ones included (`skipsInPlayback`
    /// flags them). The book screen, Contents and chapter advance all read this order.
    func playOrder(of folder: Folder) -> [Page] {
        (try? context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: .manual))) ?? []
    }

    static func ordered(_ folders: [Folder]) -> [Folder] {
        folders.sorted { a, b in
            if (a.kind == .favorites) != (b.kind == .favorites) { return a.kind == .favorites }
            if a.sortKey != b.sortKey { return a.sortKey < b.sortKey }
            return a.id.uuidString < b.id.uuidString
        }
    }

    // MARK: - Saving the context

    /// Saves pending changes, then does the audio work planned with them; false (logged) when
    /// SwiftData refuses, and the work waits for the save that stores its changes.
    @discardableResult
    func commit(_ what: String) -> Bool {
        do {
            try saveContext(context)
        } catch {
            log("save failed (\(what)): \(error)")
            ListenTimingLog.log("library_save_failed", ["what": what, "error": "\(error)"])
            return false
        }
        doPlannedAudioWork()
        return true
    }

    // MARK: - Logging

    static func short(_ id: UUID?) -> String { id.map { String($0.uuidString.prefix(8)) } ?? "-" }

    func log(_ message: String) {
        print("[Library] \(message)")
        ListenDebugLog.shared.append("lib: \(message)")
    }
}

/// Where the pre-library data lives, read by the migration: the frozen `bookmarks.json` and the
/// listen history in UserDefaults.
struct LegacyLibrarySources {
    var bookmarksURL: URL
    var defaults: UserDefaults

    static var standard: LegacyLibrarySources {
        LegacyLibrarySources(bookmarksURL: LegacyBookmarks.defaultFileURL, defaults: .standard)
    }
}
