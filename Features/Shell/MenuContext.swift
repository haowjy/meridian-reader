import SwiftUI

/// What the ⋯ panel shows, by the surface that opened it. Each case carries only the state its
/// rows need and the handler for its own actions, so no surface sees (or has to ignore) another
/// surface's buttons.
///
/// Bottom row of big buttons, rightmost (nearest the thumb, the panel's focus point) last:
/// - browse:  `[Favorites][History][Reader]`
/// - reader:  `[Favorites][History][Website]`
/// - Now Playing: `[Favorites][History][Website]`
/// - library: `[Favorites][History][Browser]`
enum MenuContext {
    case browse(BrowseMenu, perform: (BrowseMenu.Action) -> Void)
    case reader(ReaderMenu, perform: (ReaderMenu.Action) -> Void)
    case nowPlaying(NowPlayingMenu, perform: (NowPlayingMenu.Action) -> Void)
    case library(LibraryMenu, perform: (LibraryMenu.Action) -> Void)
}

/// The web page / start page menu.
struct BrowseMenu {
    enum Action {
        case newSearch, saveToLibrary, removeFromLibrary, toggleFavorite, share, reload, voiceSettings
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
    /// Developer options: the Debug › submenu with this toggle. nil hides it.
    var fakeExtractionFailure: Binding<Bool>?
}

/// The Reader sheet's menu (over the browser or the library).
struct ReaderMenu {
    enum Action {
        case voiceSettings, toggleSave, moveTo, toggleFavorite, share, listenDebug
        case favorites, history, openWebsite
    }

    var isSaved: Bool
    var canSave: Bool
    var isFavorite: Bool
    var canFavorite: Bool
    var canShare: Bool
    /// The article has a web page to go to.
    var canOpenWebsite: Bool
    /// Developer options: the Debug row (listen debug panel).
    var showsDebug: Bool
}

/// Now Playing's menu: what you hear, not the surface under it.
struct NowPlayingMenu {
    enum Action {
        case voiceSettings, share, listenDebug
        case favorites, history, openWebsite
    }

    var canShare: Bool
    /// The playing page has a web page to go to.
    var canOpenWebsite: Bool
    /// Developer options: the Debug row (listen debug panel).
    var showsDebug: Bool
}

/// The Library's menu, for the screen on top: the home, a folder, the top level's pages, a book
/// or series. Nothing in it acts on the browser's page.
struct LibraryMenu {
    enum Screen: Equatable {
        case home
        /// A plain folder or Favorites (`isFavorites`: only Sort and New Folder Inside).
        case folder(isFavorites: Bool)
        /// The pages in no folder (*Pages · Show All*).
        case pages
        case book(isSeries: Bool)
    }

    enum Action {
        case voiceSettings, newFolder, importBook, sort(PageSort), rename, move, deleteFolder, deleteDownloads, listenDebug
        case favorites, history, browser
    }

    var screen: Screen
    /// *Import Book…* on the home and plain folders (the Library surface; the Favorites sheet
    /// has none, since the Files picker can't open over a sheet).
    var canImportBook = false
    /// The screen's page sort (folders and the top level's pages).
    var sort: PageSort = .manual
    /// Developer options: the Debug row (listen debug panel), last on every screen.
    var showsDebug = false
}
