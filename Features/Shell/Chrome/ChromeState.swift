import CoreGraphics

/// The places the chrome's pill switches between, in the pill's order. Listen is not one of them:
/// it slides up over everything (`ShellState.isNowPlayingPresented`), and the chrome's Listen button opens it.
enum ChromeDestination: CaseIterable, Equatable {
    case library, browse, settings
}

/// Everything the compact chrome is drawn from. A pure value (no UIKit, no observation) so
/// `ChromeLayout` and the rules below are checkable without a screen; `ChromeHost` builds one from
/// the app's state.
struct ChromeState: Equatable {
    var destination: ChromeDestination
    /// How far a scroll down has folded the rows: 0 two rows, 0.5 one row, 1 the bubble.
    /// Continuous, driven by scrolling down (`ChromeScroll`); a scroll up of `revealDistance` brings
    /// both rows back at once.
    var progress: CGFloat = 0
    /// An in-place reader's full screen (a scroll down or its middle tap): nothing is drawn.
    var fullScreen = false
    /// The browser has somewhere to go back to / forward to (‹ ›). A new page has neither.
    var canGoBack = false
    var canGoForward = false
    /// The Browser shows a page, not its start page: ⌂ ends the arrows' capsule.
    var canGoHome = false
    /// A search is editing: the one-row keyboard form.
    var keyboard = false
    /// The Browser shows its page as the Reader draws it, in place (a Library page read in place is
    /// the Library's own). It never folds: an in-place reader is expanded or full screen
    /// (`ChromePolicy.reads`).
    var readerMode = false
    /// A Library selection's action bar is row 2: the chrome stays expanded.
    var editing = false
    /// The bubble's width once folded (`ChromeMetrics.bubbleWidth`): the host measures its title.
    var bubbleWidth: CGFloat = Control.small
    /// The home indicator's strip under the safe area (0 on a phone with a Home button): the rows end
    /// on its top, the bubble inside it (`ChromeMetrics.bubbleClearance` above the screen's edge).
    var homeInset: CGFloat = ChromeMetrics.homeIndicatorStrip

    /// Edit holds the chrome expanded, whatever the scroll says (its bar is row 2). Every other screen
    /// that never folds (an in-place reader, the start page) is held by its policy (`ChromeScroll.policy`),
    /// which never lets progress rise.
    var collapse: CGFloat { editing ? 0 : min(1, max(0, progress)) }

    /// How far the rows have folded: not while the keyboard is up (its own one-row form).
    var fold: CGFloat { keyboard ? 0 : collapse }

    /// Everything but the fold, which animates by itself: what the host animates a step at a time.
    var discrete: ChromeState {
        var state = self
        state.progress = 0
        return state
    }
}
