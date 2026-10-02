import SwiftUI

/// What the ⋯ panel shows, by the surface that opened it. Each case carries only the state its
/// rows need and the handler for its own actions, so no surface sees (or has to ignore) another
/// surface's buttons.
///
/// Bottom row of big buttons, rightmost (nearest the thumb, the panel's focus point) last:
/// - browse:  `[Bookmarks][Saved][History][Reader]`
/// - reader:  `[Bookmarks][Saved][History][Website]`
/// - library: `[Bookmarks][History][Browser]`
enum MenuContext {
    case browse(BrowseMenu, perform: (BrowseMenu.Action) -> Void)
    case reader(ReaderMenu, perform: (ReaderMenu.Action) -> Void)
    case library(perform: (LibraryMenuAction) -> Void)
}

/// The web page / start page menu.
struct BrowseMenu {
    enum Action {
        case newSearch, toggleSave, toggleBookmark, share, reload, voiceSettings
        case bookmarks, saved, history, openReader
    }

    var hasPage: Bool
    /// A readable page, and no extraction already running.
    var canOpenReader: Bool
    var isSaved: Bool
    var canSave: Bool
    var isBookmarked: Bool
    var canBookmark: Bool
    var canShare: Bool
    /// Developer options: the Debug › submenu with this toggle. nil hides it.
    var fakeExtractionFailure: Binding<Bool>?
}

/// The reader's menu (✕ over the browser or ‹ in the library).
struct ReaderMenu {
    enum Action {
        case voiceSettings, toggleSave, toggleBookmark, share, listenDebug
        case bookmarks, saved, history, openWebsite
    }

    var isSaved: Bool
    var canSave: Bool
    var isBookmarked: Bool
    var canBookmark: Bool
    var canShare: Bool
    /// The article has a web page to go to.
    var canOpenWebsite: Bool
    /// Developer options: the Debug row (listen debug panel).
    var showsDebug: Bool
}

/// The library list's menu: nothing in it acts on the browser's page.
enum LibraryMenuAction {
    case voiceSettings, bookmarks, history, browser
}
