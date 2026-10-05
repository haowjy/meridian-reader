import Foundation
import SwiftData

/// Something in the tree a move or a delete acts on.
enum LibraryItem {
    case folder(Folder)
    case page(Page)
}

/// Why the tree refused a change.
enum LibraryTreeError: Error, Equatable {
    /// A folder into itself or one of its own subfolders.
    case cycle
    /// Books and series take pages only from their source, and no subfolders.
    case fixedDestination
    /// A book's or series' pages never leave it.
    case leavesFixedFolder
    /// Favorites stays at the top level, keeps its name and can't be deleted.
    case favoritesIsPinned
}

/// What a folder holds, all the way down (`LibraryStore.contents(of:)`).
struct FolderContents: Equatable {
    var folders = 0
    var pages = 0
    var books = 0
    var pageKeys: Set<UUID> = []

    /// "2 folders, 27 pages, 1 book"; nil when empty.
    var summary: String? {
        let parts = [(folders, "folder"), (pages, "page"), (books, "book")]
            .filter { $0.0 > 0 }
            .map { count, noun in "\(count) \(noun)\(count == 1 ? "" : "s")" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Order among siblings as a fractional `Double`: a move writes only the moved items' keys, and
/// the siblings are renumbered in one pass only once a gap gets too small to split.
enum FractionalOrder {
    /// Below this gap the siblings are renumbered.
    static let minimumGap = 1e-9

    /// Gives `moving` keys that place them, in order, just before `before` among `siblings`
    /// (ordered by `key`; the end if `before` is nil or one of `moving`).
    static func move<Item: AnyObject>(_ moving: [Item], among siblings: [Item], before: Item?,
                                      key: ReferenceWritableKeyPath<Item, Double>) {
        guard !moving.isEmpty else { return }
        let movingIDs = Set(moving.map(ObjectIdentifier.init))
        let rest = siblings.filter { !movingIDs.contains(ObjectIdentifier($0)) }
        let insertAt = before.flatMap { b in rest.firstIndex { $0 === b } } ?? rest.count
        let low = insertAt > 0 ? rest[insertAt - 1][keyPath: key] : (rest.first?[keyPath: key] ?? 0) - 1
        let high = insertAt < rest.count ? rest[insertAt][keyPath: key] : low + Double(moving.count + 1)
        let step = (high - low) / Double(moving.count + 1)
        if step < minimumGap {
            var ordered = rest
            ordered.insert(contentsOf: moving, at: insertAt)
            for (i, item) in ordered.enumerated() { item[keyPath: key] = Double(i) }
        } else {
            for (i, item) in moving.enumerated() { item[keyPath: key] = low + step * Double(i + 1) }
        }
    }
}

/// The folder tree: making, renaming, moving, sorting and deleting folders. Folders nest to any
/// depth; books, series and Favorites have the rules in `LibraryTreeError`. Each change saves at
/// once; a save that fails is rolled back and throws `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// A new plain folder at the end of `parent` (the top level if nil).
    @discardableResult
    func makeFolder(name: String, in parent: Folder?) throws -> Folder {
        if let parent, parent.kind.isFixed { throw LibraryTreeError.fixedDestination }
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: .plain,
                            sortKey: nextFolderSortKey(in: parent), createdAt: now())
        context.insert(folder)
        folder.parent = parent
        try commitOrRollBack("make folder")
        return folder
    }

    func rename(_ folder: Folder, to name: String) throws {
        guard folder.kind != .favorites else { throw LibraryTreeError.favoritesIsPinned }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        try commitOrRollBack("rename folder")
    }

    /// The folder's page order. Books and series stay in source order.
    func setSort(_ sort: PageSort, for folder: Folder) throws {
        guard !folder.kind.isFixed else { return }
        folder.pageSort = sort
        try commitOrRollBack("sort")
    }

    /// Moves `items` to the end of `destination` (the top level if nil), in the given order.
    /// Refuses the whole move, changing nothing, if any item can't go there; a move whose save
    /// fails leaves every item where it was, in its order.
    func move(_ items: [LibraryItem], to destination: Folder?) throws {
        for item in items { try checkMove(item, to: destination) }
        var folderKey = nextFolderSortKey(in: destination)
        var pageKey = nextSortKey(in: destination)
        for item in items {
            switch item {
            case .folder(let folder):
                guard folder.parent !== destination else { continue }
                folder.parent = destination
                folder.sortKey = folderKey
                folderKey += 1
            case .page(let page):
                guard page.folder !== destination else { continue }
                page.setFolder(destination)
                page.sortKey = pageKey
                pageKey += 1
            }
        }
        try commitOrRollBack("move")
    }

    private func checkMove(_ item: LibraryItem, to destination: Folder?) throws {
        if let destination, destination.kind.isFixed { throw LibraryTreeError.fixedDestination }
        switch item {
        case .folder(let folder):
            if folder.kind == .favorites, destination != nil { throw LibraryTreeError.favoritesIsPinned }
            if let destination, destination === folder || destination.ancestors.contains(where: { $0 === folder }) {
                throw LibraryTreeError.cycle
            }
        case .page(let page):
            if page.isInFixedFolder, page.folder !== destination { throw LibraryTreeError.leavesFixedFolder }
        }
    }

    /// Deletes a folder. `keepContents` (*Delete Folder Only*): its subfolders and pages move up
    /// to its parent (the top level if none), after the parent's own contents, in their order.
    /// Otherwise (*Delete Folder and Contents*, *Delete Book*) everything inside goes, books
    /// included; playback of any of it stops first, and the audio goes once the delete is saved.
    /// A book or series is always deleted with its chapters: they never leave it.
    func deleteFolder(_ folder: Folder, keepContents: Bool) throws {
        try deleteFolders([folder], keepContents: keepContents)
    }

    /// Deletes `folders` in one save, each as `deleteFolder` does: plain folders keep or lose
    /// their contents by `keepContents`, books and series go with their chapters either way.
    /// Refuses Favorites, changing nothing. A save that fails is rolled back and throws: every
    /// folder, page and its audio stay.
    func deleteFolders(_ folders: [Folder], keepContents: Bool) throws {
        if folders.contains(where: { $0.kind == .favorites }) { throw LibraryTreeError.favoritesIsPinned }
        for folder in folders where !folder.isDeleted {
            if keepContents && !folder.kind.isFixed {
                moveContentsUp(folder)
            } else {
                deleteRecursively(folder)
            }
        }
        try commitOrRollBack("delete folder")
    }

    private func moveContentsUp(_ folder: Folder) {
        let parent = folder.parent
        var folderKey = nextFolderSortKey(in: parent)
        for child in subfolders(of: folder) {
            child.parent = parent
            child.sortKey = folderKey
            folderKey += 1
        }
        var pageKey = nextSortKey(in: parent)
        for page in pages(in: folder) {
            page.setFolder(parent)
            page.sortKey = pageKey
            pageKey += 1
        }
        log("delete folder \(folder.name), contents moved up")
        context.delete(folder)
    }

    /// What *Delete Folder and Contents* would delete, for its confirmation.
    func contentsCount(of folder: Folder) -> (folders: Int, pages: Int) {
        subfolders(of: folder).reduce((folders: 0, pages: pages(in: folder).count)) { total, child in
            let inner = contentsCount(of: child)
            return (total.folders + 1 + inner.folders, total.pages + inner.pages)
        }
    }

    private func deleteRecursively(_ folder: Folder) {
        for child in subfolders(of: folder) { deleteRecursively(child) }
        for page in pages(in: folder) { deleteWithoutSaving(page) }
        log("delete folder \(folder.name) and contents")
        context.delete(folder)
    }

    /// Moves `pages` (siblings in `folder`, or in no folder) to just before `before` (the end if
    /// nil): one fractional `sortKey` write per page, renumbering the siblings in one pass when
    /// a gap gets under `FractionalOrder.minimumGap`. Not for books and series.
    func reorder(_ pages: [Page], in folder: Folder?, before: Page?) throws {
        guard folder?.kind.isFixed != true else { return }
        let siblings: [Page]
        if let folder {
            siblings = (try? context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: .manual))) ?? []
        } else {
            siblings = (try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.folderID == nil },
                                                                 sortBy: LibraryQueries.sortDescriptors(.manual)))) ?? []
        }
        FractionalOrder.move(pages, among: siblings, before: before, key: \.sortKey)
        try commitOrRollBack("reorder")
    }

    /// Moves `folders` (siblings under `parent`, or at the top level) to just before `before` (the
    /// end if nil), the same way. Favorites stays first among the top-level folders whatever its
    /// key.
    func reorderFolders(_ folders: [Folder], in parent: Folder?, before: Folder?) throws {
        let siblings = parent.map(subfolders(of:)) ?? topLevelFolders()
        FractionalOrder.move(folders, among: siblings, before: before, key: \.sortKey)
        try commitOrRollBack("reorder folders")
    }

    /// What deleting `folder` and its contents takes with it, for the confirmation: subfolders,
    /// pages, and books and series (whose chapters aren't counted as pages), and every page key
    /// (to say "Stops what's playing").
    func contents(of folder: Folder) -> FolderContents {
        var total = FolderContents()
        total.pageKeys.formUnion(pages(in: folder).map(\.listenKey))
        if folder.kind.isFixed { return total }
        total.pages += pages(in: folder).count
        for child in subfolders(of: folder) {
            if child.kind.isFixed { total.books += 1 } else { total.folders += 1 }
            let inner = contents(of: child)
            total.folders += inner.folders
            total.pages += inner.pages
            total.books += inner.books
            total.pageKeys.formUnion(inner.pageKeys)
        }
        return total
    }

    /// A sort key after every subfolder of `parent` (or every top-level folder).
    func nextFolderSortKey(in parent: Folder?) -> Double {
        let siblings = parent.map(subfolders(of:)) ?? topLevelFolders()
        return (siblings.map(\.sortKey).max() ?? -1) + 1
    }
}
