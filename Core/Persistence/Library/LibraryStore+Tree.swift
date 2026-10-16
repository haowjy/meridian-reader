import Foundation
import SwiftData

/// Something in the tree a move or a delete acts on.
enum LibraryItem {
    case folder(Folder)
    case page(Page)
}

/// Why the tree refused a change. Every folder takes pages and subfolders, books and series too
/// (decision D19); only these are refused.
enum LibraryTreeError: Error, Equatable {
    /// A folder into itself or one of its own subfolders.
    case cycle
}

/// What a folder holds, all the way down (`LibraryStore.contents(of:)`).
struct FolderContents: Equatable {
    var folders = 0
    var pages = 0
    var pageKeys: Set<UUID> = []

    /// "2 folders, 27 pages"; nil when empty.
    var summary: String? {
        let parts = [(folders, "folder"), (pages, "page")]
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
/// depth, books and series as any other (decision D19); only cycles are refused. Each change
/// saves at once; a save that fails is rolled back and throws
/// `LibraryStoreError.saveFailed`.
extension LibraryStore {
    /// A new plain folder named `name` ("New Folder" when it is nil or blank) at the end of
    /// `parent` (the top level if nil).
    @discardableResult
    func makeFolder(name: String?, in parent: Folder?) throws -> Folder {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try edit("make folder") {
            let folder = Folder(name: trimmed.isEmpty ? String(localized: "New Folder") : trimmed, kind: .plain,
                                sortKey: nextFolderSortKey(in: parent), createdAt: now())
            context.insert(folder)
            folder.parent = parent
            return folder
        }
    }

    func rename(_ folder: Folder, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try edit("rename folder") { folder.name = trimmed }
    }

    /// *Edit Details*: the name, byline and cover in one edit. A blank name keeps the name; a blank
    /// byline clears it; a nil cover removes it. The kind never changes, so a plain folder given
    /// details keeps its order and still takes drops (decision D17).
    func setDetails(of folder: Folder, name: String, byline: String?, cover: Data?) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let byline = byline?.trimmingCharacters(in: .whitespacesAndNewlines)
        try edit("folder details") {
            if !name.isEmpty { folder.name = name }
            folder.byline = byline?.isEmpty == false ? byline : nil
            if folder.coverData != cover { folder.coverData = cover }
        }
    }

    /// The folder's page order: *Manual* (a book's or series' starts as the source's), *Newest* or
    /// *Title*.
    func setSort(_ sort: PageSort, for folder: Folder) throws {
        try edit("sort") { folder.pageSort = sort }
    }

    /// Moves `items` to the end of `destination` (the top level if nil), in the given order.
    /// Refuses the whole move, changing nothing, if any item can't go there; a move whose save
    /// fails leaves every item where it was, in its order.
    func move(_ items: [LibraryItem], to destination: Folder?) throws {
        for item in items { try checkMove(item, to: destination) }
        try edit("move") {
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
                    movePlaceOff(page)
                    page.setFolder(destination)
                    page.sortKey = pageKey
                    pageKey += 1
                }
            }
        }
    }

    /// Why `item` can't go into `destination` (the top level if nil), or nil when it can: the
    /// rules every move, Move tree pick and drop follows (`LibraryTreeError`). Asked while a row is
    /// dragged over a folder, so the folder shows whether it takes the drop.
    func moveRefusal(_ item: LibraryItem, to destination: Folder?) -> LibraryTreeError? {
        guard case .folder(let folder) = item else { return nil }
        if let destination, destination === folder || destination.ancestors.contains(where: { $0 === folder }) {
            return .cycle
        }
        return nil
    }

    private func checkMove(_ item: LibraryItem, to destination: Folder?) throws {
        if let refusal = moveRefusal(item, to: destination) { throw refusal }
    }

    /// Deletes a folder, a book or series as any other. `keepContents`: its subfolders and pages
    /// move up to its parent (the top level if none), after the parent's own contents, in their
    /// order (no screen offers it, decision D18). Otherwise (*Delete Folder and Contents*)
    /// everything inside goes; playback of any of it stops first, and the audio goes once the
    /// delete is saved.
    func deleteFolder(_ folder: Folder, keepContents: Bool) throws {
        try deleteFolders([folder], keepContents: keepContents)
    }

    /// Deletes `folders` in one save, each as `deleteFolder` does, keeping or losing their contents
    /// by `keepContents`. A save that fails is rolled back and throws: every folder, page and its
    /// audio stay.
    func deleteFolders(_ folders: [Folder], keepContents: Bool) throws {
        try edit("delete folder") {
            for folder in folders where !folder.isDeleted {
                if keepContents {
                    moveContentsUp(folder)
                } else {
                    deleteRecursively(folder)
                }
            }
        }
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

    private func deleteRecursively(_ folder: Folder) {
        for child in subfolders(of: folder) { deleteRecursively(child) }
        for page in pages(in: folder) { deleteWithoutSaving(page) }
        log("delete folder \(folder.name) and contents")
        context.delete(folder)
    }

    /// Places `pages` just before `before` (the end if nil) among the pages of `folder` (the top
    /// level if nil), in their order, coming from wherever they are: Edit's drag handles, and a
    /// row dropped between rows. One fractional `sortKey` write per page, renumbering the siblings
    /// in one pass when a gap gets under `FractionalOrder.minimumGap`.
    ///
    /// The order becomes the folder's own (*Manual*). `shownIn` is the sort the pages are shown
    /// in, where the drop was made: when it isn't *Manual*, the siblings are first numbered in
    /// that order, so the page lands between the rows it was dropped between. (The top level's
    /// sort is kept on the device, `LibraryTopLevel`; its caller switches it.)
    ///
    /// One save; a save that fails leaves every page where it was, in its order.
    func arrange(_ pages: [Page], in folder: Folder?, before: Page?, shownIn sort: PageSort) throws {
        for page in pages { try checkMove(.page(page), to: folder) }
        try edit("arrange") {
            let shown = folder.map { LibraryQueries.pages(inFolder: $0.id, sort: sort) } ?? LibraryQueries.loosePages(sort: sort)
            let siblings = (try? context.fetch(shown)) ?? []
            if sort != .manual {
                for (index, page) in siblings.enumerated() { page.sortKey = Double(index) }
            }
            folder?.pageSort = .manual
            for page in pages where page.folder !== folder {
                movePlaceOff(page)
                page.setFolder(folder)
            }
            FractionalOrder.move(pages, among: siblings, before: before, key: \.sortKey)
        }
    }

    /// Places `folders` just before `before` (the end if nil) among the subfolders of `parent`
    /// (the top level if nil), coming from wherever they are, the same way. Refuses, changing
    /// nothing, what `move` refuses: a folder into itself or below itself.
    func arrange(_ folders: [Folder], in parent: Folder?, before: Folder?) throws {
        for folder in folders { try checkMove(.folder(folder), to: parent) }
        try edit("arrange folders") {
            let siblings = parent.map(subfolders(of:)) ?? topLevelFolders()
            for folder in folders where folder.parent !== parent { folder.parent = parent }
            FractionalOrder.move(folders, among: siblings, before: before, key: \.sortKey)
        }
    }

    /// What deleting `folder` and its contents takes with it, for the confirmation: subfolders
    /// (books and series among them) and pages, all the way down, and every page key (to say
    /// "Stops what's playing").
    func contents(of folder: Folder) -> FolderContents {
        let pages = pages(in: folder)
        var total = FolderContents(pages: pages.count, pageKeys: Set(pages.map(\.listenKey)))
        for child in subfolders(of: folder) {
            let inner = contents(of: child)
            total.folders += 1 + inner.folders
            total.pages += inner.pages
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
