import SwiftUI
import UIKit

/// The bars of a reading page (the Reader and Now Playing) and full screen.
///
/// The text fills the screen; the header (top bar, the ☝︎ hint) and the bottom band are drawn over
/// it (`ReadingBars`), and the text's scroll view insets its content by what floats over it
/// (`insets`), so the first line starts below the header and the last scrolls clear of the band.
/// Full screen (`hidden`) slides the bars off their edges and hides the status bar; the bottom
/// inset drops to the home indicator's strip, so the end of the text scrolls down to it, and the
/// text on screen stays where it is (`ScrollTextLayout.setInsets`). On compact width the whole
/// bottom chrome goes with them (`ReadingInPlace`).
///
/// - **Full screen is a tap in the middle of the text, in and out, and nothing else**
///   (`tappedCentre`). Scrolling never enters or leaves it; a tap at either edge turns a screen
///   (`revealFloatingControl`) and leaves the bars as they are (`TapZone`). On regular width a pull
///   down at the top of the text brings the bars back (`pulledDownAtTop`); compact full screen is
///   left by the middle tap alone.
/// - In full screen what floats over the text (the small play / pause at the bottom right, and
///   Jump to Audio while the text is away from the audio) shows as one group (`floatingControl`)
///   until `floatingDuration` after full screen begins, a scroll by a finger, an edge tap (a page
///   turn) or a tap on it, then fades together. A tap in the middle brings the bars back instead,
///   and they carry the play control.
/// - While VoiceOver runs the bars never hide (`ReadingBars` shows them when it starts). The ☝︎
///   jump mode and the popovers keep them without a rule here: the web view reports nothing in
///   jump mode, and a popover or the ⋯ menu takes every touch until it closes.
///
/// One per reading page, for its life (`ReadingBars` puts it in its content's environment). What
/// scrolls the text reads it there: the reading web view feeds it drags and taps.
@MainActor
@Observable
final class ReadingChrome {
    /// Full screen: the bars and the status bar are hidden. A sheet keeps it here; a page in place
    /// reads the compact chrome's (`present`), so there is one copy.
    var hidden: Bool { fullScreen?.wrappedValue ?? ownHidden }
    private var ownHidden = false
    @ObservationIgnored private var fullScreen: Binding<Bool>?
    /// The header's height and what floats at the foot (the band, the room under it, the home
    /// indicator's inset; in full screen, Scroll mode, the home indicator's inset alone): the room
    /// the text leaves. Set by `ReadingBars`; the top is unchanged by `hidden`.
    var insets = ReaderTextInsets()
    /// The home indicator's inset (the bottom safe area), measured by `ReadingBars`: Pages mode's footer
    /// sits on it.
    var homeIndicator: CGFloat = 0
    /// Pages mode's footer, above the home indicator (0 in Scroll mode), measured by the reading
    /// view: in full screen what floats over the text sits above it.
    var pageFooter: CGFloat = 0
    /// The line of the pill floating over the text while it shows (Jump to Audio, the in-place
    /// readers' Listen: the pill and the gap under it), set by `OverTextPill`: in Scroll mode the
    /// end of the text scrolls clear of it (`ReadingBars`).
    var overTextClearance: CGFloat = 0
    /// The same line, for a pill that stays while the page shows (the in-place readers' Listen):
    /// Pages' card ends above it (`ReadingPagesCard`). 0 for Jump to Audio, which may float over
    /// the card's foot.
    var pageCardClearance: CGFloat = 0
    /// What floats over the text shows (only in full screen).
    private(set) var floatingControl = false
    /// When it fades: each reveal pushes this on, so a scroll's many reveals share one timer.
    @ObservationIgnored private var floatingUntil = ContinuousClock.now

    /// How long the floating play / pause stays after it appears.
    static let floatingDuration: Duration = .seconds(3)

    /// Compact width: where the text's own scrolling goes (the chrome host's collapse), as an
    /// offset from the text's top; set by `present`. Not called in full screen.
    @ObservationIgnored var onUserScroll: (CGFloat) -> Void = { _ in }
    /// Compact width: the text moved without a finger deciding anything (a restore, following the
    /// audio, a scrub, or any move in full screen); the collapse measures from here next.
    @ObservationIgnored var onScrollAnchor: (CGFloat) -> Void = { _ in }
    @ObservationIgnored private var floatingTimer: Task<Void, Never>?
    /// A pull down at the top of the text in full screen brings the bars back: true only for a
    /// regular-width sheet (`ReadingShowing.sheet`). Compact full screen, Listen's and in place, is
    /// left by the middle tap alone.
    @ObservationIgnored private var pullShowsBars = false

    /// How the page is shown (`ReadingPage`, before its first frame). In place, full screen is the
    /// compact chrome's, and the text's scrolling goes to it.
    func present(_ showing: ReadingShowing) {
        switch showing {
        case .sheet:
            pullShowsBars = true
        case .cover:
            pullShowsBars = false
        case .inPlace(let place):
            pullShowsBars = false
            fullScreen = place.fullScreen
            onUserScroll = place.scrolled
            onScrollAnchor = place.anchored
        }
    }

    #if DEBUG
    /// `-readerFullScreen`: the first reading page shown (in place or Listen) goes full screen 3 s
    /// after it opens, as a middle tap does. Set by the launch (`AppMain`).
    static var opensInFullScreen = false

    /// The page is up (`ReadingBars`): full screen in 3 s if the launch asked for it.
    func opensInFullScreenIfAsked() async {
        guard Self.opensInFullScreen else { return }
        Self.opensInFullScreen = false
        try? await Task.sleep(for: .seconds(3))
        hide()
    }
    #endif

    private func setHidden(_ value: Bool) {
        if let fullScreen { fullScreen.wrappedValue = value } else { ownHidden = value }
    }

    /// A finger scrolled the text to `offset` (0 at its top). Full screen takes no part in it.
    func userScrolled(to offset: CGFloat) {
        guard hidden else { return onUserScroll(offset) }
        onScrollAnchor(offset)
        revealFloatingControl()
    }

    /// The text is at `offset` without a finger having moved it.
    func textMoved(to offset: CGFloat) {
        onScrollAnchor(offset)
    }

    /// A pull down at the top of the text: in full screen on a regular-width sheet, the bars come back.
    func pulledDownAtTop() {
        guard pullShowsBars else { return }
        show()
    }

    /// A tap in the middle of the text: full screen toggles.
    func tappedCentre() {
        hidden ? show() : hide()
    }

    /// A scroll, an edge tap (a page turn) or a tap on the floating play / pause itself: in full
    /// screen what floats shows for another `floatingDuration`.
    func revealFloatingControl() {
        guard hidden else { return }
        floatingUntil = .now + Self.floatingDuration
        if !floatingControl { floatingControl = true }
        guard floatingTimer == nil else { return }
        floatingTimer = Task { [weak self] in
            while let until = self?.floatingUntil, ContinuousClock.now < until {
                try? await Task.sleep(until: until)
                if Task.isCancelled { return }
            }
            self?.floatingControl = false
            self?.floatingTimer = nil
        }
    }

    /// Full screen's floating group is up.
    var showsFloating: Bool { hidden && floatingControl }

    /// The bars come back (over the text: nothing moves).
    func show() {
        guard hidden else { return }
        setHidden(false)
        floatingTimer?.cancel()
        floatingTimer = nil
        floatingControl = false
    }

    private func hide() {
        guard !hidden, !UIAccessibility.isVoiceOverRunning else { return }
        setHidden(true)
        revealFloatingControl()
    }

    /// Where a tap on the text lands, across its width: the left edge's first `edgeMargin`
    /// points do nothing (an edge swipe never becomes a tap), the rest of the left 30% goes back
    /// a screen, the right 30% forward, the middle toggles the bars.
    enum TapZone: Equatable {
        case none
        case previous
        case centre
        case next

        static let edgeMargin: CGFloat = 48

        init(x: CGFloat, width: CGFloat) {
            if x < Self.edgeMargin {
                self = .none
            } else if x < width * 0.3 {
                self = .previous
            } else if x > width * 0.7 {
                self = .next
            } else {
                self = .centre
            }
        }
    }
}

/// Where the spoken sentence is, from the visible text: Jump to Audio's arrow points that way.
enum JumpDirection {
    /// Above the visible text (it is earlier in the article; Pages: on an earlier page).
    case up
    /// Below it.
    case down
}

/// Room the text leaves for the bars drawn over it (points; the bottom includes the home
/// indicator's inset).
struct ReaderTextInsets: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

/// The play / pause floating at the bottom right of a reading page in full screen, while
/// `ReadingChrome.floatingControl` says so: a small accent disc (`PlayStateButton`'s
/// `disc` at `Control.bar`) with the floating shadow. A tap on it plays or pauses and keeps it a while
/// longer. Goes in the page's `overText`, which places it above the home indicator.
struct FloatingPlayButton: View {
    let state: PlayState
    let action: () -> Void

    @Environment(\.readingChrome) private var chrome

    var body: some View {
        ZStack {
            if let chrome, chrome.showsFloating {
                PlayStateButton(state: state, look: .disc(size: Control.bar, glyph: Glyph.small)) {
                    chrome.revealFloatingControl()
                    action()
                }
                .overTextShadow()
                .accessibilityIdentifier("fullScreenPlayPause")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Spacing.pageMargin)
        .animation(chrome?.showsFloating == true ? Motion.snappy : Motion.fadeOut, value: chrome?.showsFloating == true)
    }
}

extension EnvironmentValues {
    /// Set by `ReadingBars` on its content; nil elsewhere (no full screen).
    @Entry var readingChrome: ReadingChrome? = nil
}
