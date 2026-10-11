import Foundation
import Observation
import SwiftData

/// The one entry point for library reads and writes: the folder tree, pages, saving, favorites,
/// the launch maintenance (migration, dedupe, layout, prune). One page per canonical URL,
/// app-wide; every content delete also removes the page's audio, which is why nothing else
/// deletes `Folder` or `Page` rows.
///
/// Lists in views read through `LibraryQueries` (with `@Query`); everything that changes the
/// library comes here. The one save path is `ArticleSaveCoordinator` → `save(_:placement:playhead:)`.
@MainActor
@Observable
final class LibraryStore {
    /// A page not in the Library is kept this long after it was last played.
    static let unsavedKeepInterval: TimeInterval = 7 * 24 * 60 * 60

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let tts: LocalTTSCoordinator
    /// Stops playback when the session is playing this key: a page about to be deleted or
    /// revised (before its audio is deleted or aligned), or a key a waiting merge would move onto
    /// such a page (`keysWaitingToMerge`).
    @ObservationIgnored var stopPlaybackIfPlaying: (UUID) -> Void = { _ in }
    /// A merge (dedupe, a *Replace* finding a chapter's text under a new key) moved the page with
    /// the first key into the page with the second, which holds the text the third names
    /// (`textFingerprint(of:)`, nil for none): whatever holds the first key outside the library
    /// follows, the live session only while it plays that text
    /// (`SpeechController.rekeyActiveSession`).
    @ObservationIgnored var keyMerged: (UUID, UUID, String?) -> Void = { _, _, _ in }
    /// Favorites whose icon `backfillFavoriteIcons` already fetched this launch.
    @ObservationIgnored var iconTried = Set<UUID>()
    /// How `commit` saves; tests make it fail.
    @ObservationIgnored var saveContext: (ModelContext) throws -> Void = { try $0.save() }
    /// How the stored audio work is read, in order; tests make it fail.
    @ObservationIgnored var fetchAudioWork: (ModelContext) throws -> [LibraryAudioWork] = {
        try $0.fetch(FetchDescriptor<LibraryAudioWork>(sortBy: [SortDescriptor(\.sequence)]))
    }
    /// Audio work planned with the changes not saved yet (`LibraryStore+AudioWork`).
    @ObservationIgnored var audioPlan = LibraryAudioWorkPlan()
    /// Listening progress written and not stored yet, by page key (`LibraryStore+PendingListening`).
    @ObservationIgnored var pendingListening: [UUID: PendingListening] = [:]
    /// The last stored text `textFingerprint(of:)` hashed, with its fingerprint.
    @ObservationIgnored var lastTextHashed: (data: Data, fingerprint: String)?
    /// An edit is being staged (`edit`): `commit` stores nothing until the edit's own save.
    @ObservationIgnored private(set) var isStagingEdit = false
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

    /// The pages in the Library in no folder, in `sort`.
    func loosePages(sort: PageSort) -> [Page] {
        (try? context.fetch(LibraryQueries.loosePages(sort: sort))) ?? []
    }

    /// The order a folder plays in: a book's or series' chapters by `sortKey`, skipped ones
    /// included (`skipsInPlayback` flags them); any other folder's pages in its sort, as its
    /// screen lists them. The book screen, Contents and carrying on all read this order.
    func playOrder(of folder: Folder) -> [Page] {
        pages(in: folder)
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
    /// SwiftData refuses, and the work waits for the save that stores its changes. While an edit
    /// is being staged (`edit`) it stores nothing and returns false: what was written waits for
    /// that edit's save, or its rollback.
    @discardableResult
    func commit(_ what: String) -> Bool {
        guard !isStagingEdit else {
            log("save (\(what)) waits for the edit being staged")
            return false
        }
        do {
            try saveChanges()
        } catch {
            log("save failed (\(what)): \(error)")
            ListenTimingLog.log("library_save_failed", ["what": what, "error": "\(error)"])
            return false
        }
        doPlannedAudioWork()
        return true
    }

    /// Saves every change in the context; once that succeeds, the listening progress among them
    /// is stored.
    func saveChanges() throws {
        try saveContext(context)
        pendingListening = [:]
    }

    /// An edit someone asked for (a save, a move, a rename, a mark, a remove, a delete): `stage`
    /// writes it to the context, then one save stores it. A save that fails is rolled back
    /// (`rollBack`) and throws `LibraryStoreError.saveFailed`, so the edit neither shows as done
    /// nor waits in the context for a later save to store, or a later rollback to drop.
    ///
    /// While `stage` runs, `commit` stores nothing: it would store the edit half made. `stage`
    /// can cause a commit: deleting the playing page stops it, and stopping records its position.
    /// That progress is kept (`PendingListening`): the edit's save stores it, or its rollback
    /// writes it again. Refusals (`LibraryTreeError`) are thrown before `stage`, which can't fail.
    @discardableResult
    func edit<Result>(_ what: String, _ stage: () -> Result) throws -> Result {
        // An edit made inside another (while its stage runs) is saved with that one.
        guard !isStagingEdit else { return stage() }
        isStagingEdit = true
        let result = stage()
        isStagingEdit = false
        guard commit(what) else {
            rollBack()
            throw LibraryStoreError.saveFailed
        }
        return result
    }

    /// After a failed save: the context's changes and the audio work planned with them are
    /// dropped, and every model they changed or deleted reads what the store holds again. The
    /// listening progress among them is then written again (`writeListeningAgain`), for the next
    /// save to store: a failed edit costs no listening history.
    ///
    /// SwiftData's `rollback()` leaves a model already in memory showing the values it rolled
    /// back, relationships included (a book's `pages` still listing a chapter the change
    /// inserted), until that model is fetched again; it notifies no observer. Callers hold such
    /// models (the progress recorder its page, a screen its folder). A fetch returns the same
    /// instance holding the stored values, so each one is fetched again by its id. Models the
    /// change inserted leave the context with it.
    func rollBack() {
        let touched = context.changedModelsArray + context.deletedModelsArray
        context.rollback()
        audioPlan = LibraryAudioWorkPlan()
        for model in touched { refetch(model) }
        writeListeningAgain()
    }

    private func refetch<Model: PersistentModel>(_ model: Model) {
        let id = model.persistentModelID
        var descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        _ = try? context.fetch(descriptor)
    }

    // MARK: - Logging

    static func short(_ id: UUID?) -> String { id.map { String($0.uuidString.prefix(8)) } ?? "-" }

    func log(_ message: String) {
        print("[Library] \(message)")
        ListenDebugLog.shared.append("lib: \(message)")
    }
}

/// A library write that didn't happen.
enum LibraryStoreError: Error, Equatable {
    /// SwiftData refused the save; nothing changed.
    case saveFailed
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
