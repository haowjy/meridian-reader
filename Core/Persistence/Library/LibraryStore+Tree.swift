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

/// The folder tree: making, renaming, moving, sorting and deleting folders. Folders nest to any
/// depth; books, series and Favorites have the rules in `LibraryTreeError`.
extension LibraryStore {
    /// A new plain folder at the end of `parent` (the top level if nil).
    @discardableResult
    func makeFolder(name: String, in parent: Folder?) throws -> Folder {
        if let parent, parent.kind.isFixed { throw LibraryTreeError.fixedDestination }
        let folder = Folder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: .plain,
                            sortKey: nextFolderSortKey(in: parent), createdAt: now())
        context.insert(folder)
        folder.parent = parent
        commit("make folder")
        return folder
    }

    func rename(_ folder: Folder, to name: String) throws {
        guard folder.kind != .favorites else { throw LibraryTreeError.favoritesIsPinned }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        commit("rename folder")
    }

    /// The folder's page order. Books and series stay in source order.
    func setSort(_ sort: PageSort, for folder: Folder) {
        guard !folder.kind.isFixed else { return }
        folder.pageSort = sort
        commit("sort")
    }

    /// Moves `items` to the end of `destination` (the top level if nil), in the given order.
    /// Refuses the whole move, changing nothing, if any item can't go there.
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
        commit("move")
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
    /// included, with their audio; playback of any of it stops first.
    func deleteFolder(_ folder: Folder, keepContents: Bool) throws {
        guard folder.kind != .favorites else { throw LibraryTreeError.favoritesIsPinned }
        if keepContents && !folder.kind.isFixed {
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
        } else {
            deleteRecursively(folder)
        }
        commit("delete folder")
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
    /// a gap gets under 1e-9. Not for books and series.
    func reorder(_ pages: [Page], in folder: Folder?, before: Page?) {
        guard folder?.kind.isFixed != true else { return }
        let siblings: [Page]
        if let folder {
            siblings = (try? context.fetch(LibraryQueries.pages(inFolder: folder.id, sort: .manual))) ?? []
        } else {
            siblings = (try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.folderID == nil },
                                                                 sortBy: LibraryQueries.sortDescriptors(.manual)))) ?? []
        }
        let moving = Set(pages.map(ObjectIdentifier.init))
        let rest = siblings.filter { !moving.contains(ObjectIdentifier($0)) }
        let insertAt = before.flatMap { b in rest.firstIndex { $0 === b } } ?? rest.count
        let low = insertAt > 0 ? rest[insertAt - 1].sortKey : (rest.first?.sortKey ?? 0) - 1
        let high = insertAt < rest.count ? rest[insertAt].sortKey : low + Double(pages.count + 1)
        let step = (high - low) / Double(pages.count + 1)
        if step < 1e-9 {
            var ordered = rest
            ordered.insert(contentsOf: pages, at: insertAt)
            for (i, page) in ordered.enumerated() { page.sortKey = Double(i) }
        } else {
            for (i, page) in pages.enumerated() { page.sortKey = low + step * Double(i + 1) }
        }
        commit("reorder")
    }

    /// A sort key after every subfolder of `parent` (or every top-level folder).
    func nextFolderSortKey(in parent: Folder?) -> Double {
        let siblings = parent.map(subfolders(of:)) ?? topLevelFolders()
        return (siblings.map(\.sortKey).max() ?? -1) + 1
    }
}
