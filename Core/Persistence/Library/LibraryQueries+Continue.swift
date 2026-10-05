import Foundation

/// One entry in Continue: a book or series (resumes at its place), or a page.
enum ContinueItem {
    case folder(Folder)
    case page(Page)

    var lastPlayedAt: Date? {
        switch self {
        case .folder(let folder): folder.lastPlayedAt
        case .page(let page): page.lastPlayedAt
        }
    }
}

/// Continue: what you were listening to, most recent first.
extension LibraryQueries {
    /// Continue's items: books and series played and unfinished (`continueFolders`), and pages
    /// part-way through (`isPartWay`) from `recentlyPlayed` and `undatedInProgress`, most
    /// recently played first, at most `continueLimit`.
    static func continueItems(folders: [Folder], recent: [Page], undated: [Page]) -> [ContinueItem] {
        let pages = continuePages(recent: recent, undated: undated)
        let dated = (folders.map(ContinueItem.folder) + pages.filter { $0.lastPlayedAt != nil }.map(ContinueItem.page))
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        let undatedItems = pages.filter { $0.lastPlayedAt == nil }.map(ContinueItem.page)
        return Array((dated + undatedItems).prefix(continueLimit))
    }

    /// Continue's pages: saved pages and pages not in the Library, part-way, outside books and
    /// series (those resume through their folder). Link pages never show. Dated pages first,
    /// most recently played first, then undated ones newest saved first.
    static func continuePages(recent: [Page], undated: [Page]) -> [Page] {
        var seen = Set<ObjectIdentifier>()
        let picked = (recent + undated).filter { page in
            seen.insert(ObjectIdentifier(page)).inserted && page.isSaved && !page.isInFixedFolder && isPartWay(page)
        }
        return picked.sorted { a, b in
            switch (a.lastPlayedAt, b.lastPlayedAt) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.addedAt ?? .distantPast) > (b.addedAt ?? .distantPast)
            }
        }
    }

    /// Unfinished, and played (any position counts, even the first paragraph) or, for a page
    /// listened to before listening was dated, past the start and not parked on its last
    /// paragraph.
    static func isPartWay(_ page: Page) -> Bool {
        guard page.finishedAt == nil else { return false }
        if page.lastPlayedAt != nil { return true }
        guard page.positionParagraph > 0 || page.positionUTF16 > 0 else { return false }
        let count = page.paragraphCount
        return !(count > 1 && page.positionParagraph >= count - 1)
    }
}
