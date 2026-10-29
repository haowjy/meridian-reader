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
    /// How far a scroll down has folded both rows into the capsule: 0 expanded, 1 folded. Continuous,
    /// driven by scrolling (`ChromeScroll`); only a tap on the capsule brings the rows back.
    var progress: CGFloat = 0
    /// The Reader's full screen: nothing is drawn.
    var fullScreen = false
    /// Something has played: ▶ shows, with its progress ring (never on Listen: the card has one).
    var played = false
    /// The browser has somewhere to go back to / forward to (‹ ›). A new page has neither.
    var canGoBack = false
    var canGoForward = false
    /// A search is editing: the one-row keyboard form.
    var keyboard = false
    /// The Browser shows its page as the Reader draws it, in place (a Library page read in place is
    /// the Library's own). It folds on a scroll like any page, in Scroll mode only (`ChromeHost`).
    var readerMode = false
    /// A Library selection's action bar is row 2: the chrome stays expanded.
    var editing = false
    /// The capsule's width once folded (`ChromeMetrics.capsuleWidth`): the host measures its title.
    var capsuleWidth: CGFloat = ChromeMetrics.capsuleHeight

    /// Listen and Edit hold the chrome expanded, whatever the scroll says: Listen's card is the player
    /// (and its text is followed by the audio), so scrolling it never takes it away. Reader mode in
    /// Pages mode is held by the host (`ChromeScroll.holdsExpanded`), which never lets progress rise.
    var collapse: CGFloat { destination == .reader || editing ? 0 : min(1, max(0, progress)) }

    /// How far the two rows have folded into the capsule: not while the keyboard is up (its own one-row form).
    var capsule: CGFloat { keyboard ? 0 : collapse }

    /// Everything but the capsule fold, which animates by itself: what the host animates a step at a time.
    var discrete: ChromeState {
        var state = self
        state.progress = 0
        return state
    }
}
