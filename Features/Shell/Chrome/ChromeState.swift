import CoreGraphics

/// The three places the chrome's pill switches between. The Reader is a destination like the
/// others: `.reader` is the lit segment while the Reader or Now Playing is up.
enum ChromeDestination: CaseIterable, Equatable {
    case reader, library, browse
}

/// How much of the chrome shows: two independent flags. `collapsed` is every compact screen
/// scrolled down; `fullScreen` is the Reader's. Leaving full screen returns to whatever
/// `collapsed` was, because nothing in full screen touches it.
struct ChromePresence: Equatable {
    var collapsed = false
    var fullScreen = false
}

/// Everything the compact chrome is drawn from: a destination, its presence, and the context the
/// pieces depend on. A pure value (no UIKit, no observation) so `ChromeGeometry` and the rules
/// below are checkable without a screen; `ChromeHost` builds one from the app's state.
struct ChromeState: Equatable {
    var destination: ChromeDestination
    var presence = ChromePresence()
    /// Something has played: the ▶ ring shows.
    var played = false
    /// The browser has somewhere to go back to / forward to (‹ ›).
    var canGoBack = false
    var canGoForward = false
    /// A search is editing: one row, the field takes the width.
    var keyboard = false
    /// The Browser shows its page as the Reader draws it, in place (Browser only): the chrome stays expanded.
    var readerMode = false
    /// A Library selection's action bar is row 2: the chrome stays expanded.
    var editing = false

    enum Rows: Equatable {
        /// Row 1 (the screen's own) over row 2 (the pill).
        case two
        /// The one row.
        case one
        /// Nothing: the Reader's full screen.
        case none
    }

    var rows: Rows {
        if destination == .reader, presence.fullScreen { return .none }
        if keyboard { return .one }
        return presence.collapsed && !readerMode && !editing ? .one : .two
    }
}
