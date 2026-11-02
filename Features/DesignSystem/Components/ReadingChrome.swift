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
/// - **Full screen is a tap in the middle of the text, in and out** (`tappedCentre`). A tap at either
///   edge turns a screen and leaves the bars as they are (`TapZone`). On
///   regular width a pull down at the top of the text brings the bars back (`pulledDownAtTop`).
///   Listen's full screen is left by the middle tap alone. In place, full screen is the compact
///   chrome's (`ReadingInPlace.fullScreen`), and in Scroll mode a deliberate scroll down enters it and a
///   scroll up of 24 pt leaves it, however it began (`ChromeScroll`'s reading rule): this page only
///   reports its scroll, and from `hidden` down nothing knows which hand flipped it.
/// - In full screen what floats over the text (the small play / pause at the bottom right, and
///   Jump to Audio while the text is away from the audio) stays for as long as full screen does:
///   it never fades on its own. A tap in the middle brings the bars back instead, and they carry
///   the play control.
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
    /// The line of Jump to Audio while it shows (the pill and the gap under it), set by
    /// `OverTextPill`: in Scroll mode the end of the text scrolls clear of it (`ReadingBars`).
    var overTextClearance: CGFloat = 0
    /// In place: where the text's own scrolling goes (the compact chrome), as an offset from the
    /// text's top; set by `present`.
    @ObservationIgnored var onUserScroll: (CGFloat) -> Void = { _ in }
    /// In place: the text moved without a finger deciding anything (a restore, following the audio, a
    /// scrub, a reflow) or a drag began; the chrome measures from here next.
    @ObservationIgnored var onScrollAnchor: (CGFloat) -> Void = { _ in }
    /// A pull down at the top of the text in full screen brings the bars back: true only for a
    /// regular-width sheet (`ReadingShowing.sheet`). Listen's full screen is left by the middle tap
    /// alone; in place, the compact chrome's reading rule reads the pull as a scroll up.
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

    /// A finger scrolled the text to `offset` (0 at its top): in place, the compact chrome decides
    /// what it does.
    func userScrolled(to offset: CGFloat) {
        onUserScroll(offset)
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

    /// The bars come back (over the text: nothing moves).
    func show() {
        guard hidden else { return }
        setHidden(false)
    }

    private func hide() {
        guard !hidden, !UIAccessibility.isVoiceOverRunning else { return }
        setHidden(true)
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

/// The play / pause floating at the bottom right of a reading page for as long as it is in full
/// screen: a small accent disc (`PlayStateButton`'s `disc` at `Control.bar`) with the floating
/// shadow. Goes in the page's `overText`, which places it above the home indicator.
struct FloatingPlayButton: View {
    let state: PlayState
    let action: () -> Void

    @Environment(\.readingChrome) private var chrome

    var body: some View {
        ZStack {
            if let chrome, chrome.hidden {
                PlayStateButton(state: state, look: .disc(size: Control.bar, glyph: Glyph.small), action: action)
                .overTextShadow()
                .accessibilityIdentifier("fullScreenPlayPause")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Spacing.pageMargin)
        .animation(chrome?.hidden == true ? Motion.snappy : Motion.fadeOut, value: chrome?.hidden == true)
    }
}

extension EnvironmentValues {
    /// Set by `ReadingBars` on its content; nil elsewhere (no full screen).
    @Entry var readingChrome: ReadingChrome? = nil
}
