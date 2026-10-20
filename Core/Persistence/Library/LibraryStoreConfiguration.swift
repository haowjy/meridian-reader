import Foundation
import SwiftData
import CoreData

/// The app's one `ModelContainer`, over two store files:
/// - **"local"** holds `SavedArticle` (frozen since the library migration) and `RecentVisit` at
///   the URL `ModelContainer(for:)` used before there were two stores, `default.store`, so the
///   existing data opens in place;
/// - **"library"** holds `Folder`, `Article`, the migration's receipts and pending audio work in
///   `library.store`.
///
/// The library lives in its own file because an older build reopening a single shared store
/// would drop the entities it doesn't know; a file it never opens survives a rollback.
enum LibraryStoreConfiguration {
    static let localName = "local"
    static let libraryName = "library"

    static var localModels: [any PersistentModel.Type] { [SavedArticle.self, RecentVisit.self] }
    static var libraryModels: [any PersistentModel.Type] { [Folder.self, Article.self, LibraryMigrationReceipt.self, LibraryAudioWork.self] }

    /// The app's container, over the two files. The local one is where `ModelConfiguration()`
    /// resolves to.
    static func makeContainer(localURL: URL = AppDirectories.localStore,
                              libraryURL: URL = AppDirectories.libraryStore) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Each store file holds the whole schema (both configurations), as SwiftData writes it.
        try LibraryEntityRename.migrateIfNeeded(at: libraryURL, types: localModels + libraryModels)
        let local = ModelConfiguration(localName, schema: Schema(localModels), url: localURL)
        let library = ModelConfiguration(libraryName, schema: Schema(libraryModels), url: libraryURL)
        return try ModelContainer(for: Schema(localModels + libraryModels), configurations: [local, library])
    }

    /// Both configurations in memory (tests).
    static func makeInMemoryContainer() throws -> ModelContainer {
        let local = ModelConfiguration(localName, schema: Schema(localModels), isStoredInMemoryOnly: true)
        let library = ModelConfiguration(libraryName, schema: Schema(libraryModels), isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(localModels + libraryModels), configurations: [local, library])
    }
}

/// The library store written before C121 named the item entity `Page` and three of `Folder`'s
/// fields after it. SwiftData can rename a field (`originalName`) but not an entity, and would
/// drop every `Page` row as an entity it no longer knows. So before the container opens, a store
/// that still has `Page` is migrated in place by Core Data: an inferred lightweight migration from
/// the model cached in the store to today's, with the old names as renaming identifiers, so every
/// row, field, external blob and relationship is kept. The files are copied to
/// `LibraryBackup-C121` first. If the migration fails the launch stops, rather than let SwiftData
/// open the store and drop the rows.
enum LibraryEntityRename {
    /// Today's name to the name the store has, for entities and for each entity's fields.
    static let entities = ["Article": "Page"]
    static let fields = ["Folder": ["articleSortRaw": "pageSortRaw", "currentArticleKey": "currentPageKey",
                                    "articles": "pages"]]

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Whether the store at `url` still has the old names (metadata only, nothing opened).
    static func needsMigration(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url),
              let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] else { return false }
        return entities.values.contains { hashes[$0] != nil } && !entities.keys.contains { hashes[$0] != nil }
    }

    static func migrateIfNeeded(at url: URL, types: [any PersistentModel.Type]) throws {
        guard needsMigration(at: url) else { return }
        guard let destination = NSManagedObjectModel.makeManagedObjectModel(for: types)?.copy() as? NSManagedObjectModel else {
            throw Failure(description: "library rename: couldn't build the model")
        }
        for entity in destination.entities {
            let name = entity.name ?? ""
            if let old = entities[name] { entity.renamingIdentifier = old }
            for property in entity.properties { if let old = fields[name]?[property.name] { property.renamingIdentifier = old } }
        }
        try backUp(url)
        // The store keeps the model it was written with (Core Data's model cache), which is the
        // source of the inferred lightweight migration; it runs in place on the SQLite file.
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        let container = NSPersistentContainer(name: "library", managedObjectModel: destination)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw Failure(description: "library rename: \(failure)") }
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        guard !needsMigration(at: url) else { throw Failure(description: "library rename: the store still has the old names") }
    }

    /// Copies the store's files (the database, its journal and its external blobs) aside, once.
    private static func backUp(_ url: URL) throws {
        let files = FileManager.default
        let folder = url.deletingLastPathComponent().appending(path: "LibraryBackup-C121")
        guard !files.fileExists(atPath: folder.path) else { return }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        let support = "." + url.deletingPathExtension().lastPathComponent + "_SUPPORT"
        for part in [name, name + "-wal", name + "-shm", support] {
            let from = url.deletingLastPathComponent().appending(path: part)
            if files.fileExists(atPath: from.path) { try files.copyItem(at: from, to: folder.appending(path: part)) }
        }
    }
}
