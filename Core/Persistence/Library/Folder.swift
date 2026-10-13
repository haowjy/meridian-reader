import Foundation
import SwiftData

/// Where a folder came from. Stored as `Folder.kindRaw`; the raw values are persisted and never
/// change. Every folder follows the same rules (decision D19): it takes drops and subfolders, its
/// pages move in and out, and its order is yours. Book and series origin remain metadata for
/// Replace, playback, dedupe and audio trimming; display appearance comes from folder details.
enum FolderKind: String, Codable, CaseIterable {
    /// A folder the user made.
    case plain
    /// Made by importing an EPUB: one page per chapter, first in the book's order.
    case book
    /// A web serial: one page per chapter, first in the order they were found.
    case series
    /// Legacy Favorites folder, migrated to independent star flags at launch.
    case favorites

    /// Made from a book or a web serial: its pages are chapters.
    var isBookOrSeries: Bool { self == .book || self == .series }
}

/// How a folder (or the top level) orders its pages. Raw values are persisted.
enum PageSort: String, Codable, CaseIterable {
    case manual
    case newest
    case title
}

/// A folder in the library tree, in the "library" store (`LibraryStoreLocation`). CloudKit-shaped:
/// every property optional or defaulted, no `.unique`, every relationship optional with an
/// inverse and `.nullify`. Content deletes go through `LibraryStore`, which also removes audio;
/// a cascade would strand it.
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = FolderKind.plain.rawValue
    /// Order among its siblings. Fractional, so a move is one write.
    var sortKey: Double = 0
    var createdAt: Date = Date.now
    /// A book's or series' is *Manual* until changed: its pages start in the source's order.
    var pageSortRaw: String = PageSort.manual.rawValue
    /// An item can be favorited without changing where it lives in the tree.
    var isFavorite: Bool = false

    // Details. A book or series starts with its source's; any folder's are edited in *Edit
    // Details* (`LibraryStore.setDetails`). Favorites has none.
    var byline: String?
    /// A thumbnail (`CoverThumbnail`), never the full-size image.
    @Attribute(.externalStorage) var coverData: Data?
    /// Series: the contents page, or the first chapter.
    var sourceURLString: String?
    /// Book: the book key. Series: the canonical contents URL. Dedupe merges folders sharing it.
    var sourceIdentifier: String?
    /// Codable per kind: series finder state; a book's file fingerprint and chapter keys
    /// (`BookSourceState`).
    var sourceStateData: Data?
    var languageCode: String?

    // Listening.
    /// The page that last played: where Continue resumes.
    var currentPageKey: UUID?
    var lastPlayedAt: Date?
    /// Set when the last playable page finishes; cleared when one in it plays again.
    var finishedAt: Date?

    var parent: Folder?
    // The inverse is declared on this side only: the macro rejects reciprocal `inverse:`
    // annotations on a self-reference.
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent) var children: [Folder]? = []
    @Relationship(deleteRule: .nullify, inverse: \Page.folder) var pages: [Page]? = []

    init(id: UUID = UUID(), name: String, kind: FolderKind = .plain, sortKey: Double = 0, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.sortKey = sortKey
        self.createdAt = createdAt
    }

    var kind: FolderKind {
        get { FolderKind(rawValue: kindRaw) ?? .plain }
        set { kindRaw = newValue.rawValue }
    }

    var pageSort: PageSort {
        get { PageSort(rawValue: pageSortRaw) ?? .manual }
        set { pageSortRaw = newValue.rawValue }
    }

    var displayName: String { name }

    /// It has a cover or a byline: its screen has the header with the cover and the author, and its
    /// row the cover (decision D17). Details change only the look.
    var hasDetails: Bool { coverData != nil || !(byline ?? "").isEmpty }

    /// This folder and every folder above it, nearest first.
    var ancestors: [Folder] {
        var out: [Folder] = []
        var next = parent
        // A cycle (two devices moving folders into each other) is broken by dedupe; stop anyway.
        while let folder = next, !out.contains(where: { $0 === folder }), folder !== self {
            out.append(folder)
            next = folder.parent
        }
        return out
    }

    /// 1 for a top-level folder.
    var depth: Int { ancestors.count + 1 }
}
