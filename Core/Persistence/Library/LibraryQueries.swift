import Foundation
import SwiftData

/// Every library list's fetch, in one place: which lists a page is in is decided here and nowhere
/// else. A page is in exactly one of three standings, and the star is a flag beside them:
///
/// - **In the Library** (`addedAt` set): its folder's list (`articles(inFolder:)`) or the top level's
///   pages on the home's Everything (`looseArticles`), Everything's search (`searchArticles`), address
///   suggestions (`savedInLibrary`).
/// - **In Recent** (`recent`, `isInRecent`): played without saving, out of the Library, not
///   removed since you last listened to it. The home's Recent tab and its search.
/// - **Removed** (out of the Library with `removedAt` set): in none of those, nor the bar's
///   resume (`lastPlayed`). *Remove from Library* (and *Remove from Recent*, the same remove)
///   takes a page out of every one of them at once (and stops it if you hear it); saving it brings
///   it back, and so does listening to it again (🎧, the Reader's Listen).
/// - **Starred** (`isFavorite`), whatever its standing: Favorites (`favoriteArticles`, and the
///   Favorites tab's search). Remove leaves the star, so a removed favorite stays in Favorites,
///   and the prune keeps a starred page (`prunable`); only unstarring takes it out.
///
/// Downloads go by the Library's line: the Downloads list keeps what is in the Library
/// (`DownloadCenter`). The bar's resume (`lastPlayed`) and the prune (`prunable`) aren't lists:
/// they read pages by when they were played. Predicates never go through the optional `folder` relationship
/// (iOS 17 can't always translate it); they use `Article.folderID`. Optional dates are compared
/// through `?? distantPast`.
enum LibraryQueries {
    // MARK: Pages

    /// Starred pages, in the Library or not, anywhere in the tree, by title: the home's Favorites
    /// tab and the start page's grid.
    static var favoriteArticles: FetchDescriptor<Article> {
        FetchDescriptor(predicate: #Predicate<Article> { $0.isFavorite && $0.addedAt != nil },
                        sortBy: [SortDescriptor(\.title)])
    }

    /// Every saved page in the Library, newest first (address suggestions).
    static var savedInLibrary: FetchDescriptor<Article> {
        let saved = ArticleContentState.saved.rawValue
        return FetchDescriptor(predicate: #Predicate<Article> { $0.addedAt != nil && $0.contentStateRaw == saved },
                               sortBy: [SortDescriptor(\Article.addedAt, order: .reverse)])
    }

    /// The pages in no folder: the Library home's pages, in the top level's sort.
    static func looseArticles(sort: ArticleSort) -> FetchDescriptor<Article> {
        FetchDescriptor(predicate: #Predicate<Article> { $0.folderID == nil && $0.addedAt != nil },
                        sortBy: sortDescriptors(sort))
    }

    /// A folder's pages, in its sort.
    static func articles(inFolder id: UUID, sort: ArticleSort = .manual) -> FetchDescriptor<Article> {
        FetchDescriptor(predicate: #Predicate<Article> { $0.folderID == id }, sortBy: sortDescriptors(sort))
    }

    /// Recent: pages played without saving (decision D5), most recently played first: the
    /// Library home's Recent tab, until the 7-day prune (`prunable`) deletes them. A page removed
    /// (`removedAt`, *Remove from Recent* too) isn't in it until you listen to it again. Book
    /// chapters never qualify (they are always in their folder).
    static var recent: FetchDescriptor<Article> {
        let past = Date.distantPast
        let saved = ArticleContentState.saved.rawValue
        return FetchDescriptor(predicate: #Predicate<Article> {
            ($0.addedAt != nil || ($0.removedAt == nil && $0.folderID == nil && $0.contentStateRaw == saved))
                && ($0.lastPlayedAt ?? past) > past
        }, sortBy: [SortDescriptor(\Article.lastPlayedAt, order: .reverse), SortDescriptor(\Article.key)])
    }

    /// Whether `article` is in Recent, for one page in hand (a row's menu): `recent`'s own
    /// predicate, evaluated on it.
    static func isInRecent(_ article: Article) -> Bool {
        (try? recent.predicate?.evaluate(article)) == true
    }

    /// The pages played most recently, newest first, in the Library or played without saving
    /// (not removed: removing the page you hear stops it, and the bar doesn't offer it back): the
    /// band's Now Playing bar offers the first one still there to resume once nothing is bound,
    /// and the prune keeps it. A few, so a page deleted before its query updates leaves another.
    static var lastPlayed: FetchDescriptor<Article> {
        let past = Date.distantPast
        var descriptor = FetchDescriptor(predicate: #Predicate<Article> {
            ($0.addedAt != nil || $0.removedAt == nil) && ($0.lastPlayedAt ?? past) > past
        }, sortBy: [SortDescriptor(\Article.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = 3
        return descriptor
    }

    /// Pages in no list, not played since `cutoff`: out of the Library and not starred (Favorites
    /// keeps a starred one). Deleted by the prune.
    static func prunable(before cutoff: Date) -> FetchDescriptor<Article> {
        let past = Date.distantPast
        return FetchDescriptor(predicate: #Predicate<Article> {
            $0.addedAt == nil && !$0.isFavorite && ($0.lastPlayedAt ?? past) < cutoff
        })
    }

    /// Link pages whose text cache (and position) wasn't played since `cutoff`: the prune clears
    /// the cache and keeps the page.
    static func staleLinkCaches(before cutoff: Date) -> FetchDescriptor<Article> {
        let link = ArticleContentState.link.rawValue
        let past = Date.distantPast
        return FetchDescriptor(predicate: #Predicate<Article> {
            $0.contentStateRaw == link && $0.lastPlayedAt != nil && ($0.lastPlayedAt ?? past) < cutoff
        })
    }

    static func article(key: UUID) -> FetchDescriptor<Article> {
        var descriptor = FetchDescriptor(predicate: #Predicate<Article> { $0.key == key })
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Every page for a canonical URL (more than one only before dedupe).
    static func articles(canonicalURL: String) -> FetchDescriptor<Article> {
        FetchDescriptor(predicate: #Predicate<Article> { $0.canonicalURL == canonicalURL },
                        sortBy: [SortDescriptor(\Article.addedAt)])
    }

    // MARK: Folders

    static func folder(id: UUID) -> FetchDescriptor<Folder> {
        var descriptor = FetchDescriptor(predicate: #Predicate<Folder> { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// Every folder; `topLevel` picks the top level's from them.
    static var folders: FetchDescriptor<Folder> { FetchDescriptor() }

    /// The folders at the top level: the home's, beside the pages in no folder. A filter on the
    /// fetched folders, since a predicate can't go through the optional `parent` relationship
    /// (iOS 17) and a folder keeps no parent id.
    static func topLevel(_ folders: [Folder]) -> [Folder] {
        folders.filter { $0.parent == nil }
    }

    /// Starred folders, anywhere in the tree: the home's Favorites tab and the start page's grid.
    static var favoriteFolders: FetchDescriptor<Folder> {
        FetchDescriptor(predicate: #Predicate<Folder> { $0.isFavorite })
    }

    /// The legacy Favorites folders, which the launch converts to stars.
    static var favorites: FetchDescriptor<Folder> {
        let favorites = "favorites"
        return FetchDescriptor(predicate: #Predicate<Folder> { $0.kindRaw == favorites },
                               sortBy: [SortDescriptor(\Folder.createdAt)])
    }

    // MARK: The home

    /// The home's search within its tab (`tab`), across the tree: pages whose title, site or
    /// author, or excerpt holds `text`. Everything: pages in the Library; Favorites: starred pages,
    /// in the Library or not; Recent: Recent's pages. By title, then newest first, so the
    /// results keep one order.
    static func searchArticles(_ text: String, in tab: LibraryHomeTab) -> FetchDescriptor<Article> {
        let sort = [SortDescriptor(\Article.title), SortDescriptor(\Article.addedAt, order: .reverse), SortDescriptor(\Article.key)]
        switch tab {
        case .everything:
            return FetchDescriptor(predicate: #Predicate<Article> { article in
                article.addedAt != nil
                    && (article.title.localizedStandardContains(text) || article.byline.localizedStandardContains(text)
                        || article.excerpt.localizedStandardContains(text))
            }, sortBy: sort)
        case .favorites:
            return FetchDescriptor(predicate: #Predicate<Article> { article in
                article.isFavorite && article.addedAt != nil
                    && (article.title.localizedStandardContains(text) || article.byline.localizedStandardContains(text)
                        || article.excerpt.localizedStandardContains(text))
            }, sortBy: sort)
        case .recent:
            // `recent`'s rule, written again: a predicate can't call another on iOS 17.
            let past = Date.distantPast
            let saved = ArticleContentState.saved.rawValue
            return FetchDescriptor(predicate: #Predicate<Article> { article in
                (article.addedAt != nil || (article.removedAt == nil && article.folderID == nil && article.contentStateRaw == saved))
                    && (article.lastPlayedAt ?? past) > past
                    && (article.title.localizedStandardContains(text) || article.byline.localizedStandardContains(text)
                        || article.excerpt.localizedStandardContains(text))
            }, sortBy: sort)
        }
    }

    /// The home's search for folders within its tab: those whose name or author holds `text`,
    /// across the tree; on Favorites, starred ones only; Recent has none. By name, then oldest
    /// first.
    static func searchFolders(_ text: String, in tab: LibraryHomeTab) -> FetchDescriptor<Folder> {
        let sort = [SortDescriptor(\Folder.name), SortDescriptor(\Folder.createdAt)]
        switch tab {
        case .everything:
            return FetchDescriptor(predicate: #Predicate<Folder> { folder in
                folder.name.localizedStandardContains(text) || folder.byline?.localizedStandardContains(text) == true
            }, sortBy: sort)
        case .favorites:
            return FetchDescriptor(predicate: #Predicate<Folder> { folder in
                folder.isFavorite
                    && (folder.name.localizedStandardContains(text) || folder.byline?.localizedStandardContains(text) == true)
            }, sortBy: sort)
        case .recent:
            return noFolders
        }
    }

    /// No folder: Recent's.
    static var noFolders: FetchDescriptor<Folder> {
        FetchDescriptor(predicate: #Predicate<Folder> { _ in false })
    }

    // MARK: Sorts

    /// Ties fall back to the other field, then to the page key, so a folder's order is the same
    /// every time it is read.
    static func sortDescriptors(_ sort: ArticleSort) -> [SortDescriptor<Article>] {
        switch sort {
        case .manual: [SortDescriptor(\Article.sortKey), SortDescriptor(\Article.addedAt), SortDescriptor(\Article.key)]
        case .newest: [SortDescriptor(\Article.addedAt, order: .reverse), SortDescriptor(\Article.sortKey), SortDescriptor(\Article.key)]
        case .title: [SortDescriptor(\Article.title), SortDescriptor(\Article.sortKey), SortDescriptor(\Article.key)]
        }
    }
}

/// The Library home's tabs: what its one list holds (`LibraryQueries` decides which items).
enum LibraryHomeTab: String, CaseIterable {
    /// The Library: its top level's folders and pages.
    case everything
    /// Starred folders and pages, wherever they are, in the Library or not.
    case favorites
    /// Pages played without saving, most recent first. Its raw value is what `library.homeTab`
    /// stores, and stored values predate the tab's name, so it stays `"history"`.
    case recent = "history"
}
