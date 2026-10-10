import Foundation
import SwiftData

/// Every library list's fetch, in one place, so no list forgets to leave out pages that aren't in
/// the Library (`addedAt == nil`). Predicates never go through the optional `folder`
/// relationship (iOS 17 can't always translate it); they use `Page.folderID`. Optional dates are
/// compared through `?? distantPast`.
enum LibraryQueries {
    /// Continue lists at most this many books, series and pages.
    static let continueLimit = 8
    /// The page half of Continue looks at this many most recently played pages.
    static let continueCandidateLimit = 50

    // MARK: Pages

    /// Every page in the Library, any folder.
    static var inLibrary: FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> { $0.addedAt != nil })
    }

    /// Every saved page in the Library, newest first (address suggestions).
    static var savedInLibrary: FetchDescriptor<Page> {
        let saved = PageContentState.saved.rawValue
        return FetchDescriptor(predicate: #Predicate<Page> { $0.addedAt != nil && $0.contentStateRaw == saved },
                               sortBy: [SortDescriptor(\Page.addedAt, order: .reverse)])
    }

    /// The pages in no folder: the Library home's *Pages* (today's Saved list).
    static func loosePages(sort: PageSort) -> FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> { $0.folderID == nil && $0.addedAt != nil },
                        sortBy: sortDescriptors(sort))
    }

    /// A folder's pages, in its sort.
    static func pages(inFolder id: UUID, sort: PageSort = .manual) -> FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> { $0.folderID == id }, sortBy: sortDescriptors(sort))
    }

    /// The most recently played pages, any state (Continue filters them in code).
    static var recentlyPlayed: FetchDescriptor<Page> {
        let past = Date.distantPast
        var descriptor = FetchDescriptor(predicate: #Predicate<Page> { ($0.lastPlayedAt ?? past) > past },
                                         sortBy: [SortDescriptor(\Page.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = continueCandidateLimit
        return descriptor
    }

    /// Pages listened to part-way before listening was dated (no `lastPlayedAt`): position past
    /// the start, unfinished. Continue lists them after the dated ones, newest first.
    static var undatedInProgress: FetchDescriptor<Page> {
        let past = Date.distantPast
        // Both positions are non-negative: the sum is past zero when either is.
        let predicate = #Predicate<Page> { page in
            (page.lastPlayedAt ?? past) == past && (page.finishedAt ?? past) == past
                && page.positionParagraph + page.positionUTF16 > 0
        }
        var descriptor = FetchDescriptor<Page>(predicate: predicate,
                                               sortBy: [SortDescriptor(\Page.addedAt, order: .reverse)])
        descriptor.fetchLimit = continueCandidateLimit
        return descriptor
    }

    /// Titles, bylines and excerpts across the tree, in the Library only.
    static func search(_ text: String) -> FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> {
            $0.addedAt != nil && ($0.title.localizedStandardContains(text)
                || $0.byline.localizedStandardContains(text)
                || $0.excerpt.localizedStandardContains(text))
        }, sortBy: [SortDescriptor(\Page.title)])
    }

    /// Pages not in the Library, not played since `cutoff`: deleted by the prune.
    static func prunable(before cutoff: Date) -> FetchDescriptor<Page> {
        let past = Date.distantPast
        return FetchDescriptor(predicate: #Predicate<Page> { $0.addedAt == nil && ($0.lastPlayedAt ?? past) < cutoff })
    }

    /// Link pages whose text cache (and position) wasn't played since `cutoff`: the prune clears
    /// the cache and keeps the page.
    static func staleLinkCaches(before cutoff: Date) -> FetchDescriptor<Page> {
        let link = PageContentState.link.rawValue
        let past = Date.distantPast
        return FetchDescriptor(predicate: #Predicate<Page> {
            $0.contentStateRaw == link && $0.lastPlayedAt != nil && ($0.lastPlayedAt ?? past) < cutoff
        })
    }

    static func page(key: UUID) -> FetchDescriptor<Page> {
        var descriptor = FetchDescriptor(predicate: #Predicate<Page> { $0.key == key })
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Every page for a canonical URL (more than one only before dedupe).
    static func pages(canonicalURL: String) -> FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> { $0.canonicalURL == canonicalURL },
                        sortBy: [SortDescriptor(\Page.addedAt)])
    }

    // MARK: Folders

    /// Books and series played and not finished, most recent first (Continue's folder half).
    static var continueFolders: FetchDescriptor<Folder> {
        let past = Date.distantPast
        let book = FolderKind.book.rawValue
        let series = FolderKind.series.rawValue
        var descriptor = FetchDescriptor(
            predicate: #Predicate<Folder> {
                ($0.kindRaw == book || $0.kindRaw == series) && ($0.lastPlayedAt ?? past) > past && $0.finishedAt == nil
            },
            sortBy: [SortDescriptor(\Folder.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = continueLimit
        return descriptor
    }

    static func folder(id: UUID) -> FetchDescriptor<Folder> {
        var descriptor = FetchDescriptor(predicate: #Predicate<Folder> { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    static var favorites: FetchDescriptor<Folder> {
        let favorites = FolderKind.favorites.rawValue
        return FetchDescriptor(predicate: #Predicate<Folder> { $0.kindRaw == favorites },
                               sortBy: [SortDescriptor(\Folder.createdAt)])
    }

    /// Folders by name, across the tree.
    static func searchFolders(_ text: String) -> FetchDescriptor<Folder> {
        FetchDescriptor(predicate: #Predicate<Folder> { $0.name.localizedStandardContains(text) },
                        sortBy: [SortDescriptor(\Folder.name)])
    }

    // MARK: Sorts

    /// Ties fall back to the other field, then to the page key, so a folder's order is the same
    /// every time it is read.
    static func sortDescriptors(_ sort: PageSort) -> [SortDescriptor<Page>] {
        switch sort {
        case .manual: [SortDescriptor(\Page.sortKey), SortDescriptor(\Page.addedAt), SortDescriptor(\Page.key)]
        case .newest: [SortDescriptor(\Page.addedAt, order: .reverse), SortDescriptor(\Page.sortKey), SortDescriptor(\Page.key)]
        case .title: [SortDescriptor(\Page.title), SortDescriptor(\Page.sortKey), SortDescriptor(\Page.key)]
        }
    }
}
