import Foundation
import SwiftData

/// The app's one `ModelContainer`, over two store files:
/// - **"local"** holds `SavedArticle` (frozen since the library migration) and `RecentVisit` at
///   the URL `ModelContainer(for:)` used before there were two stores, `default.store`, so the
///   existing data opens in place;
/// - **"library"** holds `Folder`, `Page` and the migration's receipts in `library.store`.
///
/// The library lives in its own file because an older build reopening a single shared store
/// would drop the entities it doesn't know; a file it never opens survives a rollback.
enum LibraryStoreConfiguration {
    static let localName = "local"
    static let libraryName = "library"

    static var localModels: [any PersistentModel.Type] { [SavedArticle.self, RecentVisit.self] }
    static var libraryModels: [any PersistentModel.Type] { [Folder.self, Page.self, LibraryMigrationReceipt.self] }

    static var storeDirectory: URL { URL.applicationSupportDirectory }
    /// What `ModelConfiguration()` resolves to (`LibraryStoreConfigurationTests` checks it).
    static var localURL: URL { storeDirectory.appending(path: "default.store") }
    static var libraryURL: URL { storeDirectory.appending(path: "library.store") }

    /// The app's container, over the two files.
    static func makeContainer(localURL: URL = localURL, libraryURL: URL = libraryURL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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
