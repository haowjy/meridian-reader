import Foundation
import SwiftData

/// Every library list's fetch, in one place: which lists a page is in is decided here and nowhere
/// else. A page is in exactly one of three standings, and a list shows pages of one:
///
/// - **In the Library** (`addedAt` set): its folder's list (`pages(inFolder:)`) or the top level's
///   *Pages* (`loosePages`), Favorites while starred (`favoritePages`), the home's search
///   (`inLibrary`), address suggestions (`savedInLibrary`).
/// - **Played without saving** (`playedNotSaved`): out of the Library, played, not removed since
///   you last listened to it. The top of *Pages*, "Not saved", and the home's search.
/// - **Removed** (out of the Library with `removedAt` set): in no list. *Remove from Library*
///   takes a page out of every list it was in, at once, and playing on doesn't bring it back;
///   saving it does, and so does listening to it again (🎧, the Reader's Listen).
///
/// Downloads go by the same line: the Downloads list keeps what is in the Library
/// (`DownloadCenter`). The bar's resume (`lastPlayed`) and the prune (`prunable`) aren't lists: they read every
/// page by when it was played. Predicates never go through the optional `folder` relationship
/// (iOS 17 can't always translate it); they use `Page.folderID`. Optional dates are compared
/// through `?? distantPast`.
enum LibraryQueries {
    // MARK: Pages

    /// Every page in the Library, any folder.
    static var inLibrary: FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> { $0.addedAt != nil })
    }

    static var favoritePages: FetchDescriptor<Page> {
        FetchDescriptor(predicate: #Predicate<Page> { $0.addedAt != nil && $0.isFavorite },
                        sortBy: [SortDescriptor(\.title)])
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

    /// Pages played without saving (decision D5), most recently played first: the top of the
    /// Library home's *Pages* and the *Pages* screen, marked "Not saved", until the 7-day prune
    /// (`prunable`) deletes them. A page removed from the Library (`removedAt`) isn't one, even
    /// as it plays on, until you listen to it again. Book chapters never qualify (they are always
    /// in their folder).
    static var playedNotSaved: FetchDescriptor<Page> {
        let past = Date.distantPast
        let saved = PageContentState.saved.rawValue
        return FetchDescriptor(predicate: #Predicate<Page> {
            $0.addedAt == nil && $0.removedAt == nil && $0.folderID == nil && $0.contentStateRaw == saved
                && ($0.lastPlayedAt ?? past) > past
        }, sortBy: [SortDescriptor(\Page.lastPlayedAt, order: .reverse), SortDescriptor(\Page.key)])
    }

    /// The pages played most recently, newest first, in the Library or not (removed ones too:
    /// removing never touches what you hear): the band's Now Playing bar offers the first one
    /// still there to resume once nothing is bound. A few, so a page
    /// deleted before its query updates leaves another.
    static var lastPlayed: FetchDescriptor<Page> {
        let past = Date.distantPast
        var descriptor = FetchDescriptor(predicate: #Predicate<Page> { ($0.lastPlayedAt ?? past) > past },
                                         sortBy: [SortDescriptor(\Page.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = 3
        return descriptor
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

    static func folder(id: UUID) -> FetchDescriptor<Folder> {
        var descriptor = FetchDescriptor(predicate: #Predicate<Folder> { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    static var favorites: FetchDescriptor<Folder> {
        let favorites = "favorites"
        return FetchDescriptor(predicate: #Predicate<Folder> { $0.kindRaw == favorites },
                               sortBy: [SortDescriptor(\Folder.createdAt)])
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
