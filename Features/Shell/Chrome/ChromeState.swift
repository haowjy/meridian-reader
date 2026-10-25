import CoreGraphics

/// The three places the chrome's pill switches between. The Reader is a destination like the
/// others: `.reader` is the lit segment while the Reader or Now Playing is up.
enum ChromeDestination: CaseIterable, Equatable {
    case reader, library, browse
}

/// Everything the compact chrome is drawn from. A pure value (no UIKit, no observation) so
/// `ChromeLayout` and the rules below are checkable without a screen; `ChromeHost` builds one from
/// the app's state.
struct ChromeState: Equatable {
    var destination: ChromeDestination
    /// How far the chrome has folded to one row: 0 expanded, 1 collapsed. Continuous, driven by
    /// scrolling (`ChromeScroll`).
    var progress: CGFloat = 0
    /// The Reader's full screen: nothing is drawn.
    var fullScreen = false
    /// Something has played: ▶ shows, with its progress ring.
    var played = false
    /// The browser has somewhere to go back to / forward to (‹ ›). A new page has neither.
    var canGoBack = false
    var canGoForward = false
    /// A search is editing: the one-row keyboard form.
    var keyboard = false
    /// The Browser shows its page as the Reader draws it, in place: the chrome stays expanded.
    var readerMode = false
    /// A Library selection's action bar is row 2: the chrome stays expanded.
    var editing = false

    /// Reader mode and Edit hold the chrome expanded, whatever the scroll says.
    var collapse: CGFloat { readerMode || editing ? 0 : min(1, max(0, progress)) }

    /// How far the pill has folded into the screen icon: the keyboard's form is the collapsed one.
    var fold: CGFloat { keyboard ? 1 : collapse }

    /// Everything but the fold, which animates by itself: what the host animates a step at a time.
    var discrete: ChromeState {
        var state = self
        state.progress = 0
        return state
    }
}
