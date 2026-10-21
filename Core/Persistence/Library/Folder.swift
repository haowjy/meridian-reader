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
    /// A followed story (Follow): one page per chapter of its table of contents, in the story's
    /// order; its state is `FollowState`.
    case series
    /// Legacy Favorites folder, migrated to independent star flags at launch.
    case favorites

    /// Made from a book or a followed story: its pages are chapters.
    var isBookOrSeries: Bool { self == .book || self == .series }
}

/// How a folder (or the top level) orders its pages. Raw values are persisted.
enum ArticleSort: String, Codable, CaseIterable {
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
    @Attribute(originalName: "pageSortRaw") var articleSortRaw: String = ArticleSort.manual.rawValue
    /// An item can be favorited without changing where it lives in the tree.
    var isFavorite: Bool = false

    // Details. A book or series starts with its source's; any folder's are edited in *Edit
    // Details* (`LibraryStore.setDetails`).
    var byline: String?
    /// A thumbnail (`CoverThumbnail`), never the full-size image.
    @Attribute(.externalStorage) var coverData: Data?
    /// A followed story: its table of contents.
    var sourceURLString: String?
    /// Book: the book key. A followed story: its canonical contents URL. Dedupe merges folders
    /// sharing it.
    var sourceIdentifier: String?
    /// Codable per kind: a followed story's `FollowState`; a book's file fingerprint and chapter
    /// keys (`BookSourceState`).
    var sourceStateData: Data?
    /// Not written or read (kept as stored by older builds; persisted fields don't change).
    var languageCode: String?
    /// C138: a book or series: the one voice every chapter speaks in (the first chapter's), as a
    /// cache voice key; nil until a chapter has audio. Plain folders have none: each article keeps its own.
    var voiceID: String?

    // Listening.
    /// The page that last played: where Continue resumes.
    @Attribute(originalName: "currentPageKey") var currentArticleKey: UUID?
    /// Not written or read: when the folder's place last played is its page's `lastPlayedAt`
    /// (kept as stored by older builds; persisted fields don't change).
    var lastPlayedAt: Date?
    /// Not written or read: whether a folder is finished is worked out from its pages
    /// (`FolderProgress.isFinished`; kept as stored by older builds; persisted fields don't change).
    var finishedAt: Date?

    var parent: Folder?
    // The inverse is declared on this side only: the macro rejects reciprocal `inverse:`
    // annotations on a self-reference.
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent) var children: [Folder]? = []
    @Relationship(deleteRule: .nullify, originalName: "pages", inverse: \Article.folder) var articles: [Article]? = []

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

    var articleSort: ArticleSort {
        get { ArticleSort(rawValue: articleSortRaw) ?? .manual }
        set { articleSortRaw = newValue.rawValue }
    }

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
