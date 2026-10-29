import SwiftUI
import UIKit

/// The compact bottom chrome, one view above every destination (Reader, Library, Browser): two
/// rows expanded, a small capsule folded, none in the Reader's full screen. `ChromeState` says what is
/// drawn, `ChromeLayout` where, `ChromePieces` draws it; this view only wires them to the app.
///
/// ```
/// expanded    [‹][›][ address / Search Library          ]        row 1; Listen's is its player card
///             [ Listen | Library | Browser ][▶][  ⋯  ]          row 2: where you are, play, menu (Listen: no ▶)
/// folded                     [ example.com ]                     scrolled down: both rows are a capsule naming the page (never on Listen)
/// keyboard    [ 🔍 field                      ⊗ 🎤 ][Cancel]    the keyboard is up (or its session open): margin to margin
/// full screen (nothing)                                         the Reader's middle tap
/// ```
///
/// Scrolling down folds it by degrees (never on Listen, in a reader's Pages mode, on the Browser's
/// start page, or with VoiceOver on: those stay expanded). Scrolling up never unfolds it
/// (`ChromeScroll`): a tap on the capsule does, and so does the top of the text, a new page and
/// opening the search (while searching, a swipe up on the row lowers the keyboard). The host
/// never changes the size of what is under it, but for the Browser's page, which keeps clear of the capsule's
/// `capsuleFootprint` once folded: screens reserve `ChromeMetrics.footprint` (the Reader
/// `readerFootprint`) at the bottom and scroll under it. Reduce Motion: no travel, every
/// change of form (the fold, the keyboard, full screen) is a cross-fade.
///
/// It owns the field's focus (kept in sync with the session), the play / pause button's state and
/// what the Reader hands up (`ChromeCard`); each destination supplies its field, arrows and ⋯ as a
/// `ChromeScreen`.
struct ChromeHost: View {
    let browse: ChromeScreen
    let library: ChromeScreen
    /// The Reader's or Now Playing's player card, when one is up.
    let card: ChromeCard?

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingAppearance) private var readingAppearance
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private let playback = ChromePlayback()
    @FocusState private var focused: Bool
    /// Reduce Motion: the form drawn. A change of `live` is not drawn at once: the chrome fades out
    /// showing the old form, `shown` becomes `pending` at the bottom of the dip, and it fades in.
    @State private var shown: ChromeState?
    @State private var pending: ChromeState?
    @State private var dip = 1.0

    private var scroll: ChromeScroll { shell.chromeScroll }
    private let skin = ChromeSkin.current

    private var destination: ChromeDestination { shell.chromeDestination }
    private var screen: ChromeScreen {
        switch destination {
        case .reader: readerScreen
        case .library: library
        case .browse: browse
        }
    }
    /// The Reader has no arrows or search: its ⋯ is the reading page's own menu, with the rows only
    /// the page can run.
    private var readerScreen: ChromeScreen {
        ChromeScreen(more: AnyView(ReadingPageMoreButton(id: "chromeReaderMore", chrome: true, extraRows: card?.menuRows ?? [])))
    }
    private var session: SearchSession? { screen.session }
    private var isSearching: Bool { session?.isActive == true }

    /// The Browser or the Library shows a page as the Reader draws it, in place.
    private var readerMode: Bool {
        (destination == .browse && shell.pageReader != nil) || (destination == .library && shell.libraryReader != nil)
    }
    /// The chrome stays expanded whatever the text does: Listen's card, a reader in Pages mode (it
    /// turns pages by tap, not by scroll), the start page (it has no page to name), Library Edit (its bar is row 2) and VoiceOver (the
    /// rows are what it reads).
    private var pinned: Bool {
        destination == .reader || voiceOver || screen.editBar != nil || (readerMode && readingAppearance.layout == .pages)
            || (destination == .browse && !readerMode && !shell.web.hasPage)
    }

    /// The capsule's width: its title at the fixed size, or its maximum.
    private var capsuleWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: ChromeMetrics.capsuleFontSize, weight: .semibold)
        let text = (screen.capsuleTitle as NSString).size(withAttributes: [.font: font]).width
        return ChromeMetrics.capsuleWidth(forTextWidth: ceil(text))
    }

    /// What the app says the chrome is now. Its `progress` is the fold's end under Reduce Motion
    /// (one end or the other, never between) and 0 otherwise: the fold between is drawn by
    /// `ChromeFold`, so a scroll report redraws the pieces and not this view.
    private var live: ChromeState {
        ChromeState(destination: destination, progress: reduceMotion ? (scroll.isCollapsed ? 1 : 0) : 0, fullScreen: scroll.fullScreen, played: playback.isAvailable,
                    canGoBack: screen.canGoBack, canGoForward: screen.canGoForward, keyboard: isSearching,
                    readerMode: readerMode, editing: screen.editBar != nil, capsuleWidth: capsuleWidth)
    }

    private var state: ChromeState { reduceMotion ? shown ?? live : live }

    /// What the page under the chrome is drawn in: the reading theme on the Reader, Now Playing and
    /// the Browser's in-place reader view; nil elsewhere (the app's own surface).
    private var readingPalette: ReadingPalette? {
        guard destination == .reader || shell.pageReader != nil || shell.libraryReader != nil else { return nil }
        return readingAppearance.palette(accent: AppAppearance.shared.accent)
    }
    /// The colour of what is under the chrome: the reading theme, a web page's own background, or
    /// paper (the start page, the search layer, the Library).
    private var underColor: Color {
        if let readingPalette { return readingPalette.background }
        if destination == .browse, shell.web.hasPage, !isSearching, let page = shell.web.pageBackground {
            return Color(uiColor: page)
        }
        return Palette.paper
    }

    var body: some View {
        GeometryReader { proxy in
            ChromeFold(scroll: scroll, fixed: reduceMotion ? state.progress : nil) { progress in
                var drawn = state
                drawn.progress = progress
                return ChromePieces(state: drawn, width: proxy.size.width, screen: screen, card: card,
                                    play: playback.button, hasReader: playback.isAvailable, underColor: underColor,
                                    focus: $focused, onSelect: playback.select, onExpand: expandTapped)
            }
                .opacity(dip)
                // Folding follows the finger frame by frame (`ChromeScroll.displayed`); every other change
                // is one step. A different destination (set last, so it wins when both change) is `snappy`.
                .animation(reduceMotion ? nil : Motion.standard, value: state.discrete)
                .animation(reduceMotion ? nil : Motion.snappy, value: destination)
        }
        .frame(height: ChromeMetrics.readerFootprint)
        .environment(\.chromeSkin, skin)
        .readingSurface(readingPalette)
        .tint(Palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chromeHost")
        .onAppear { focused = session?.isFocused == true }
        .onChange(of: live, initial: true) { _, new in liveChanged(to: new) }
        .onChange(of: reduceMotion) { _, _ in
            shown = live
            dip = 1
        }
        .onChange(of: isSearching || shell.menu != nil, initial: true) { _, locked in scroll.isLocked = locked }
        .onChange(of: destination, initial: true) { _, new in
            scroll.holdsExpanded = pinned
            scroll.reset()
            focused = session?.isFocused == true
        }
        // A reader opening or closing in place is a different text driving the chrome (and ends its full screen).
        .onChange(of: readerMode) { _, _ in
            scroll.holdsExpanded = pinned
            scroll.reset()
        }
        // Pages mode, VoiceOver and the start page's page arriving hold or release the rows without a new screen.
        .onChange(of: pinned) { _, held in scroll.holdsExpanded = held }
        // Opening the search shows the field, so it brings the rows back first.
        .onChange(of: isSearching) { _, searching in
            if searching { scroll.expand() }
        }
        .onChange(of: focused) { _, isFocused in
            guard let session else { return }
            let wasIdle = !session.isActive
            session.focusChanged(isFocused, begin: screen.begin)
            // Like Safari: a session started by tapping the field selects its text.
            if isFocused, wasIdle, !session.text.isEmpty { Self.selectAllInFocusedField() }
        }
        .onChange(of: session?.isFocused == true) { _, wanted in
            if focused != wanted { focused = wanted }
        }
        .gesture(swipeUp, including: isSearching ? .all : .subviews)
    }

    // MARK: - Actions

    /// The capsule's tap, the only way back to two rows by hand: it pins them until the top of the text or a new page.
    private func expandTapped() { scroll.expandByHand() }

    /// While searching the row is the keyboard's: a swipe up on it lowers the keyboard.
    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: ChromeScroll.swipeStart)
            .onEnded { value in
                guard let session, session.isActive, ChromeScroll.isSwipeUp(value.translation) else { return }
                session.lowerKeyboard()
            }
    }

    /// Under Reduce Motion a new form is drawn by a dip: the old one fades out, the new one fades in.
    /// A change during a dip joins it: the dip lands on the latest.
    private func liveChanged(to new: ChromeState) {
        pending = new
        guard reduceMotion, let current = shown else {
            shown = new
            return
        }
        guard current != new, dip == 1 else { return }
        withAnimation(Motion.fadeOut) {
            dip = 0
        } completion: {
            shown = pending
            withAnimation(Motion.fadeIn) { dip = 1 }
        }
    }

    private static func selectAllInFocusedField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }
}

/// Draws `content` at the fold the scroll controller's smoothing has reached: it reads
/// `ChromeScroll.displayed` here, so the frames of a fold redraw this view and not `ChromeHost`.
/// `fixed` (Reduce Motion) is a fold that does not follow it.
private struct ChromeFold<Content: View>: View {
    let scroll: ChromeScroll
    let fixed: CGFloat?
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View { content(fixed ?? scroll.displayed) }
}
