import Foundation
import SwiftData

/// Where a copied legacy item came from. Raw values are persisted.
enum LegacySource: String, Codable {
    /// A `SavedArticle` row (`legacyID` is its `id`).
    case savedArticle
    /// A bookmark in `bookmarks.json` (`legacyID` is `SiteBookmark.id`).
    case bookmark
}

/// One legacy row or bookmark the library migration copied, in the library store. Inserted in
/// the same save as the pages it made, so a copy is either recorded or not done: a page deleted,
/// unsaved or removed from Favorites later never comes back from its frozen source, and an item
/// an older build made during a rollback (a new id) is copied on the next launch.
///
/// Receipts outlive the pages (deleting a page keeps its receipt). They are device-local and go
/// with the legacy data in Release B.
@Model
final class LibraryMigrationReceipt {
    var legacyID: UUID?
    var sourceRaw: String = LegacySource.savedArticle.rawValue
    var copiedAt: Date = Date.now

    init(legacyID: UUID, source: LegacySource, copiedAt: Date) {
        self.legacyID = legacyID
        self.sourceRaw = source.rawValue
        self.copiedAt = copiedAt
    }

    var source: LegacySource? { LegacySource(rawValue: sourceRaw) }
}
