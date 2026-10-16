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

    /// The faces of the *Save* / *Remove from Library* and ☆ toggles.
    var isSaved: Bool
    var isFavorite: Bool
    var save: MenuAvailability
    var favorite: MenuAvailability
    var share: MenuAvailability
    var reload: MenuAvailability
    /// The *Reader* button: a readable page, and no extraction already running.
    var reader: MenuAvailability
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

    /// *Go to <place>*: Now Playing's only (hidden in the Reader), dimmed for a page that plays
    /// from its site, which Website opens.
    var goTo: MenuAvailability = .hidden
    var place = Place(name: String(localized: "Library"), symbol: Icons.library)

    /// The faces of the *Save* / *Remove from Library* and ☆ toggles.
    var isSaved: Bool
    var isFavorite: Bool
    var save: MenuAvailability
    /// *Move to…*: a saved page.
    var moveTo: MenuAvailability
    var favorite: MenuAvailability
    var share: MenuAvailability
    /// *Download*: a saved page not downloading already.
    var download: MenuAvailability
    /// The *Website* button: the article has a web page to go to.
    var website: MenuAvailability
}

/// The Library's menu, for the screen on top: the home (the top level) or a folder (a book or
/// series as any other). Nothing in it acts on the browser's page.
struct LibraryMenu {
    enum Screen: Equatable {
        case home
        case folder(FolderRows)
    }

    /// A folder screen's own rows. A book reads *Delete Book…* and *Download Book*. *Download*:
    /// it has pages and isn't downloading already; *Delete Downloads*: some of it is downloaded or
    /// downloading.
    struct FolderRows: Equatable {
        var isBook: Bool
        var download: MenuAvailability
        var deleteDownloads: MenuAvailability
    }

    enum Action {
        case newFolder, importBook, sort(PageSort), rename, editDetails, move, deleteFolder, deleteDownloads
        case download, downloads, settings
        case favorites, history, browser
    }

    var screen: Screen
    /// The screen's page sort: the folder's, or on the home the top level's.
    var sort: PageSort
}
