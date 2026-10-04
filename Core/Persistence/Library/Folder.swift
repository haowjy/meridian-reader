import Foundation
import SwiftData

/// What a folder is. Stored as `Folder.kindRaw`; the raw values are persisted and never change.
enum FolderKind: String, Codable, CaseIterable {
    /// A folder the user made. Nests to any depth.
    case plain
    /// An imported book: chapters in source order, fixed.
    case book
    /// A web serial: chapters in source order, fixed.
    case series
    /// The one top-level Favorites folder (today's bookmarks). Can't be deleted, renamed or
    /// moved below the top level.
    case favorites

    /// Books and series keep their pages in source order: no hand reordering, no pages moved in
    /// or out, no subfolders.
    var isFixed: Bool { self == .book || self == .series }
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
    /// Books and series: manual only.
    var pageSortRaw: String = PageSort.manual.rawValue

    // Details: books and series (nil on plain folders and Favorites).
    var byline: String?
    @Attribute(.externalStorage) var coverData: Data?
    /// Series: the contents page, or the first chapter.
    var sourceURLString: String?
    /// Book: the book key. Series: the canonical contents URL. Dedupe merges folders sharing it.
    var sourceIdentifier: String?
    /// Codable per kind: series finder state, book file fingerprint.
    var sourceStateData: Data?
    var languageCode: String?

    // Listening (books and series).
    /// The chapter that last played: where Continue resumes.
    var currentPageKey: UUID?
    var lastPlayedAt: Date?
    /// Set when the last playable chapter finishes; cleared when chapters are added.
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
        get { kind.isFixed ? .manual : (PageSort(rawValue: pageSortRaw) ?? .manual) }
        set { pageSortRaw = newValue.rawValue }
    }

    /// The name shown: Favorites is named from its kind.
    var displayName: String {
        kind == .favorites ? String(localized: "Favorites") : name
    }

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
