import SwiftUI
import UIKit

/// The compact bottom chrome, one view above every destination (Reader, Library, Browser): two
/// rows expanded, one collapsed, none in the Reader's full screen. `ChromeState` says what is
/// drawn, `ChromeLayout` where, `ChromePieces` draws it; this view only wires them to the app.
///
/// ```
/// expanded    [‹][›][ address / Search Library          ]        row 1; the Reader's is its player card
///             [ Reader | Library | Browser ][▶][  ⋯  ]          row 2: where you are, play, menu
/// collapsed   [‹][›][ address ][icon][▶][⋯]                      scrolled down: one row (the Reader: its title chip)
/// keyboard    [ field                    ][icon][▶][✕]           the keyboard is up (or its session open)
/// full screen (nothing)                                         the Reader's middle tap
/// ```
///
/// Scrolling folds it by degrees in both directions (`ChromeScroll`); the icon's tap, a swipe up on
/// the row and the top of the text expand it (while searching, they lower the keyboard). The host
/// never changes the size of what is under it: screens reserve `ChromeMetrics.footprint` (the
/// Reader `readerFootprint`) at the bottom and scroll under it. Reduce Motion: no travel, every
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
    /// What the Reader names the page by: Now Playing's page, else the Reader's.
    private var readerTitle: String {
        if shell.isNowPlayingPresented, let now = speech.nowPlaying { return now.lineOne }
        guard let article = shell.readerArticle else { return "" }
        return ArticleRowTitle.lineOne(title: article.title, source: article.sourceLabel, address: article.origin.canonicalURL)
    }
    private var session: SearchSession? { screen.session }
    private var isSearching: Bool { session?.isActive == true }

    /// What the app says the chrome is now. Under Reduce Motion the fold is one end or the other,
    /// never between.
    private var live: ChromeState {
        ChromeState(destination: destination, progress: reduceMotion ? (scroll.isCollapsed ? 1 : 0) : scroll.displayed, fullScreen: scroll.fullScreen, played: playback.isAvailable,
                    canGoBack: screen.canGoBack, canGoForward: screen.canGoForward, keyboard: isSearching,
                    readerMode: destination == .browse && shell.pageReader != nil, editing: screen.editBar != nil)
    }

    private var state: ChromeState { reduceMotion ? shown ?? live : live }

    /// What the page under the chrome is drawn in: the reading theme on the Reader, Now Playing and
    /// the Browser's in-place reader view; nil elsewhere (the app's own surface).
    private var readingPalette: ReadingPalette? {
        guard destination == .reader || shell.pageReader != nil else { return nil }
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
            ChromePieces(state: state, width: proxy.size.width, screen: screen, card: card, readerTitle: readerTitle,
                         play: playback.button, hasReader: playback.isAvailable, underColor: underColor, focus: $focused, onSelect: playback.select, onExpand: expandTapped)
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
        .onChange(of: destination) { _, _ in
            scroll.reset()
            focused = session?.isFocused == true
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
        .gesture(swipeUp, including: scroll.progress >= 0.5 || isSearching ? .all : .subviews)
    }

    // MARK: - Actions

    /// The icon, the title chip and a swipe up on the row: back to two rows. While searching the
    /// row stays one, so it lowers the keyboard.
    private func expandTapped() {
        if let session, session.isActive {
            session.lowerKeyboard()
        } else {
            scroll.expand()
        }
    }

    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: ChromeScroll.swipeStart)
            .onEnded { value in
                guard scroll.progress >= 0.5 || isSearching, ChromeScroll.isSwipeUp(value.translation) else { return }
                expandTapped()
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
