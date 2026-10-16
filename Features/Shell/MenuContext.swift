import SwiftUI

/// What the ⋯ panel shows, by the surface that opened it. Each case carries only the state its
/// rows need and the handler for its own actions, so no surface sees (or has to ignore) another
/// surface's buttons.
///
/// Bottom row of big buttons, rightmost (nearest the thumb, the panel's focus point) last:
/// - browse:  `[Favorites][History][Reader]`
/// - reader (the Reader and Now Playing):  `[Favorites][History][Website]`
/// - library: `[Favorites][History][Browser]`
enum MenuContext {
    case browse(BrowseMenu, perform: (BrowseMenu.Action) -> Void)
    case reader(ReaderMenu, perform: (ReaderMenu.Action) -> Void)
    case library(LibraryMenu, perform: (LibraryMenu.Action) -> Void)

    /// Opened on a reading page (the Reader or Now Playing): the panel takes its colours.
    var isOnReadingPage: Bool {
        if case .reader = self { return true }
        return false
    }
}

/// The web page / start page menu.
struct BrowseMenu {
    enum Action {
        case newSearch, saveToLibrary, removeFromLibrary, toggleFavorite, share, reload, downloads, settings
        case favorites, history, openReader
    }

    var hasPage: Bool
    /// A readable page, and no extraction already running.
    var canOpenReader: Bool
    var isSaved: Bool
    var canSave: Bool
    var isFavorite: Bool
    var canFavorite: Bool
    var canShare: Bool
}

/// The page's menu, the same in the Reader sheet and Now Playing (decision D24): what it holds
/// is about the page, whichever sheet shows it. Now Playing adds *Go to* its folder or the
/// Library at the top.
struct ReaderMenu {
    enum Action {
        case goTo, toggleSave, moveTo, toggleFavorite, share, download, downloads, settings
        case favorites, history, openWebsite
    }

    /// Where Now Playing's page plays from, for *Go to <name>*: a folder or the Library.
    struct Place {
        let name: String
        let symbol: String
    }

    /// Now Playing: *Go to* the folder or the Library it plays from. nil (the Reader, or a page
    /// that plays from its site, which Website opens): no row.
    var goTo: Place?

    var isSaved: Bool
    var canSave: Bool
    var isFavorite: Bool
    var canFavorite: Bool
    var canShare: Bool
    /// The article has a web page to go to.
    var canOpenWebsite: Bool
    /// *Download*: a saved page not downloading already.
    var canDownload = false
}

/// The Library's menu, for the screen on top: the home (the top level) or a folder (a book or
/// series as any other). Nothing in it acts on the browser's page.
struct LibraryMenu {
    enum Screen: Equatable {
        case home
        case folder
    }

    enum Action {
        case newFolder, importBook, sort(PageSort), rename, editDetails, move, deleteFolder, deleteDownloads
        case download, downloads, settings
        case favorites, history, browser
    }

    var screen: Screen
    /// The screen's page sort: the folder's, or on the home the top level's.
    var sort: PageSort = .manual
    /// *Download Folder* (*Download Book*) for the folder on screen; nil when it is downloading
    /// already, or isn't a folder.
    var downloadTitle: String?
    /// The folder on screen is a book or series: *Delete Book…*.
    var isBook = false
}
