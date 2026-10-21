import SwiftUI
import UIKit

/// The bars of a reading sheet (the Reader and Now Playing) and full screen.
///
/// The text fills the sheet; the header (grabber, top bar, the ☝︎ hint) and the bottom band are
/// drawn over it, and the text's scroll view insets its content by their measured heights
/// (`insets`), so the first line starts below the header and the last scrolls clear of the band.
/// Full screen (`hidden`) slides the bars off their edges and hides the status bar; the insets
/// stay as they are, so the text never moves when the bars go or come back.
///
/// - A finger drag on the text moving up (scrolling down) past `hideDistance` hides the bars
///   (`dragged(by:)`); scrolling back up leaves them hidden (C105). Programmatic scrolls and a
///   drag's movement while it pulls the sheet never reach it.
/// - A tap in the middle of the text toggles them (`tappedCentre`); a tap at either edge turns
///   a screen (`revealFloatingControl`) and leaves them as they are (`TapZone`).
/// - In full screen a small play / pause floats at the bottom right (`floatingControl`) for
///   `floatingDuration` after full screen begins, an edge tap (a page turn) or a tap on it. A tap
///   in the middle brings the bars back instead, and they carry the play control.
/// - While VoiceOver runs the bars never hide (`Sheet` shows them when it starts). The ☝︎ jump mode and the popovers keep them
///   without a rule here: the web view reports nothing in jump mode, and a popover or the ⋯
///   menu takes every touch until it closes.
///
/// One per reading sheet, for its life (`Sheet(chrome:)` puts it in its content's environment).
/// What scrolls the text reads it there: the reading web view feeds it drags and taps.
@MainActor
@Observable
final class ReadingChrome {
    /// Full screen: the bars, the grabber and the status bar are hidden.
    private(set) var hidden = false
    /// The header's and the band's heights (the band's includes the home indicator's inset):
    /// the room the text leaves for them. Measured by `Sheet`; unchanged by `hidden`.
    var insets = ReaderTextInsets()
    /// The home indicator's inset (the bottom safe area), measured by `Sheet`: Pages mode's footer
    /// sits on it.
    var homeIndicator: CGFloat = 0
    /// Pages mode's footer, above the home indicator (0 in Scroll mode), measured by the reading
    /// view: in full screen what floats over the text sits above it.
    var pageFooter: CGFloat = 0
    /// The floating play / pause shows (only in full screen).
    private(set) var floatingControl = false

    /// How far the finger moves up, without turning back, before the bars hide.
    static let hideDistance: CGFloat = 16
    /// How far the finger moves down, without turning back, before they come back.
    static let showDistance: CGFloat = 8
    /// How long the floating play / pause stays after it appears.
    static let floatingDuration: Duration = .seconds(3)

    /// The finger's movement since it last turned back (down positive).
    @ObservationIgnored private var run: CGFloat = 0
    @ObservationIgnored private var floatingTimer: Task<Void, Never>?

    /// A finger drag on the text began: a new run.
    func dragBegan() {
        run = 0
    }

    /// The finger moved `delta` (down positive) during a drag on the text.
    func dragged(by delta: CGFloat) {
        guard delta != 0 else { return }
        run = (run < 0) == (delta < 0) ? run + delta : delta
        // Scrolling back up never brings them back (C105): only a tap in the middle does.
        if run <= -Self.hideDistance { hide() }
    }

    /// A tap in the middle of the text: the bars toggle.
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

/// The play / pause floating at the bottom right of a reading sheet in full screen, while
/// `ReadingChrome.floatingControl` says so: a small accent disc (`PlayStateButton`'s
/// `floatingDisc`) with the floating shadow. A tap on it plays or pauses and keeps it a while
/// longer. Goes in the sheet's `overText`, which places it above the home indicator.
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
    /// Set by `Sheet(chrome:)` on its content; nil elsewhere (no full screen).
    @Entry var readingChrome: ReadingChrome? = nil
}
