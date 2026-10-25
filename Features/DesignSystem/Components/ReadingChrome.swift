import SwiftUI
import UIKit

/// The bars of a reading page (the Reader and Now Playing) and full screen.
///
/// The text fills the screen; the header (top bar, the ☝︎ hint) and the bottom band are drawn over
/// it (`ReadingBars`), and the text's scroll view insets its content by their measured heights
/// (`insets`), so the first line starts below the header and the last scrolls clear of the band.
/// Full screen (`hidden`) slides the bars off their edges and hides the status bar; the insets
/// stay as they are, so the text never moves when the bars go or come back. On compact width the
/// whole bottom chrome goes with them (`ReadingInPlace`).
///
/// - **Full screen is a tap in the middle of the text, in and out, and nothing else**
///   (`tappedCentre`). Scrolling never enters or leaves it; a tap at either edge turns a screen
///   (`revealFloatingControl`) and leaves the bars as they are (`TapZone`). A pull down at the top
///   of the text brings the bars back (`pulledDownAtTop`).
/// - In full screen a small play / pause floats at the bottom right (`floatingControl`) for
///   `floatingDuration` after full screen begins, an edge tap (a page turn) or a tap on it. A tap
///   in the middle brings the bars back instead, and they carry the play control.
/// - While VoiceOver runs the bars never hide (`ReadingBars` shows them when it starts). The ☝︎
///   jump mode and the popovers keep them without a rule here: the web view reports nothing in
///   jump mode, and a popover or the ⋯ menu takes every touch until it closes.
///
/// One per reading page, for its life (`ReadingBars` puts it in its content's environment). What
/// scrolls the text reads it there: the reading web view feeds it drags and taps.
@MainActor
@Observable
final class ReadingChrome {
    /// Full screen: the bars, the grabber and the status bar are hidden.
    private(set) var hidden = false
    /// The header's and the band's heights (the band's includes the home indicator's inset):
    /// the room the text leaves for them. Measured by `ReadingBars`; unchanged by `hidden`.
    var insets = ReaderTextInsets()
    /// The home indicator's inset (the bottom safe area), measured by `ReadingBars`: Pages mode's footer
    /// sits on it.
    var homeIndicator: CGFloat = 0
    /// Pages mode's footer, above the home indicator (0 in Scroll mode), measured by the reading
    /// view: in full screen what floats over the text sits above it.
    var pageFooter: CGFloat = 0
    /// The floating play / pause shows (only in full screen).
    private(set) var floatingControl = false

    /// How long the floating play / pause stays after it appears.
    static let floatingDuration: Duration = .seconds(3)

    /// Compact width: where the text's own scrolling goes (the chrome host's collapse), as an
    /// offset from the text's top; set by `ReadingInPlace`. Not called in full screen.
    @ObservationIgnored var onUserScroll: (CGFloat) -> Void = { _ in }
    /// Compact width: the bars came back by a pull down at the top; the chrome expands with them.
    @ObservationIgnored var onPulledDownAtTop: () -> Void = {}
    @ObservationIgnored private var floatingTimer: Task<Void, Never>?

    /// A finger scrolled the text to `offset` (0 at its top). Full screen takes no part in it.
    func userScrolled(to offset: CGFloat) {
        guard !hidden else { return }
        onUserScroll(offset)
    }

    /// A pull down at the top of the text in full screen: the bars come back, expanded.
    func pulledDownAtTop() {
        guard hidden else { return }
        show()
        onPulledDownAtTop()
    }

    /// A tap in the middle of the text: full screen toggles.
    func tappedCentre() {
        hidden ? show() : hide()
    }

    /// An edge tap (a page turn) or a tap on the floating play / pause itself: in full screen it
    /// shows for another `floatingDuration`.
    func revealFloatingControl() {
        guard hidden else { return }
        floatingControl = true
        floatingTimer?.cancel()
        floatingTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.floatingDuration)
            guard !Task.isCancelled else { return }
            self?.floatingControl = false
        }
    }

    /// Jump to Audio's one rule, Scroll and Pages alike (C128): only with the bars up, and only
    /// while the text is away from the audio (`awayFromAudio`). Never in full screen, where the
    /// floating play / pause is the only control over the text.
    func showsJumpToAudio(awayFromAudio: Bool) -> Bool {
        awayFromAudio && !hidden
    }

    /// The bars come back (over the text: nothing moves).
    func show() {
        guard hidden else { return }
        hidden = false
        floatingTimer?.cancel()
        floatingControl = false
    }

    private func hide() {
        guard !hidden, !UIAccessibility.isVoiceOverRunning else { return }
        hidden = true
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

/// Room the text leaves for the bars drawn over it (points; the bottom includes the home
/// indicator's inset).
struct ReaderTextInsets: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}

/// The play / pause floating at the bottom right of a reading page in full screen, while
/// `ReadingChrome.floatingControl` says so: a small accent disc (`PlayStateButton`'s
/// `floatingDisc`) with the floating shadow. A tap on it plays or pauses and keeps it a while
/// longer. Goes in the page's `overText`, which places it above the home indicator.
struct FloatingPlayButton: View {
    let state: PlayState
    let action: () -> Void

    @Environment(\.readingChrome) private var chrome

    var body: some View {
        ZStack {
            if let chrome, chrome.hidden, chrome.floatingControl {
                PlayStateButton(state: state, look: .floatingDisc) {
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
        .animation(Motion.snappy, value: chrome?.floatingControl == true && chrome?.hidden == true)
    }
}

extension EnvironmentValues {
    /// Set by `ReadingBars` on its content; nil elsewhere (no full screen).
    @Entry var readingChrome: ReadingChrome? = nil
}
