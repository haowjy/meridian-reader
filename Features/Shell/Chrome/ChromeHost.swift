import SwiftUI
import UIKit

/// The compact bottom chrome, one view above the three destinations (Library, Browser, Settings): two rows
/// expanded, then one, then a small bubble naming the page as it folds, none in an in-place reader's full screen.
/// `ChromeState` says what is drawn, `ChromeLayout` where, `ChromePieces` draws it; this view only
/// wires them to the app. Listen is not under it: it slides up over everything, chrome included.
///
/// ```
/// expanded    [‹][›][⌂][ address / Search Library  ][🎧]     row 1, Listen at its end (⌂ on a Browser page)
///             [ Library  |  Browser  |  Settings      ]     row 2: where you are, margin to margin
/// one row     [‹][›][ address / Search Library     ][🎧]     a scroll down's first step: row 2 goes, row 1 drops into its place
/// folded                     ( example.com )                 the second step: the field shrunk to a bubble naming the page
/// keyboard    [ 🔍 field                      ⊗ 🎤 ][Cancel]    the keyboard is up (or its session open): margin to margin
/// full screen (nothing)                                     an in-place reader's: a scroll down or its middle tap
/// ```
///
/// What scrolling does is `policy` (`ChromePolicy`). On a web page, the Library and Settings a scroll
/// down folds it a step at a time (never on the Browser's start page, in Edit, or with VoiceOver on:
/// those stay expanded). A scroll up of 24 pt brings both rows back (`ChromeScroll.revealDistance`), and
/// so do a tap on the bubble (a short scroll down after it is ignored), the top of the text, a new page
/// and opening the search (while searching, a swipe up on the row lowers the keyboard). An in-place
/// reader never folds: it is expanded or full screen, entered by a deliberate scroll down (Scroll mode)
/// or the middle tap, left by a scroll up of 24 pt or the tap. The host never changes the size of what is under it, but for the Browser's page, which
/// keeps clear of the step drawn (`ChromeHome.footprint(step:)`): screens reserve
/// `ChromeHome.clearance(step: 0)` above the safe area and scroll under it. Reduce Motion: no travel, every
/// change of form (the fold, the keyboard) is a cross-fade; full screen is a fade of its own on the live
/// value, on the curves the reader's top group fades on, so both go and come back together.
///
/// It owns the field's focus (kept in sync with the session); each destination supplies its field
/// and arrows as a `ChromeScreen`.
struct ChromeHost: View {
    let browse: ChromeScreen
    let library: ChromeScreen
    let settings: ChromeScreen

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingAppearance) private var readingAppearance
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
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
        case .library: library
        case .browse: browse
        case .settings: settings
        }
    }
    private var session: SearchSession? { screen.session }
    private var isSearching: Bool { session?.isActive == true }

    /// The Browser or the Library shows a page as the Reader draws it, in place.
    private var readerMode: Bool {
        (destination == .browse && shell.pageReader != nil) || (destination == .library && shell.libraryReader != nil)
    }
    /// What the scroll rule reads from here (`ChromeScroll.policy(for:_:)`): the screen handing over
    /// is the shell's, at once; these follow the environment and the screens' own state.
    private var conditions: ChromeConditions {
        let screens: [(ChromeDestination, ChromeScreen)] = [(.library, library), (.browse, browse), (.settings, settings)]
        return ChromeConditions(voiceOver: voiceOver, readsByScroll: readingAppearance.layout == .scroll,
                                editing: Set(screens.filter { $0.1.editBar != nil }.map(\.0)),
                                browserHasPage: shell.web.hasPage)
    }

    /// The bubble's width: its title at the fixed size and its padding (the layout caps it to the margins).
    private var bubbleWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: TypeStyle.caption.size, weight: .semibold)
        let text = (screen.bubbleTitle as NSString).size(withAttributes: [.font: font]).width
        return ChromeMetrics.bubbleWidth(forTextWidth: ceil(text))
    }

    /// What the app says the chrome is now. Its `progress` is the fold's end under Reduce Motion
    /// (one end or the other, never between) and 0 otherwise: the fold between is drawn by
    /// `ChromeFold`, so a scroll report redraws the pieces and not this view.
    private var live: ChromeState {
        ChromeState(destination: destination, progress: reduceMotion ? ChromeScroll.stepEnd(scroll.progress) : 0, fullScreen: scroll.fullScreen,
                    canGoBack: screen.canGoBack, canGoForward: screen.canGoForward, canGoHome: screen.canGoHome,
                    keyboard: isSearching,
                    readerMode: readerMode, editing: screen.editBar != nil, bubbleWidth: bubbleWidth,
                    homeInset: ChromeHome.inset)
    }

    /// What is drawn. Under Reduce Motion the form waits for the dip, and full screen is not part of
    /// it: the host fades itself on the live value (`body`).
    private var state: ChromeState {
        guard reduceMotion else { return live }
        var drawn = shown ?? live
        drawn.fullScreen = false
        return drawn
    }

    /// What the page under the chrome is drawn in: the reading theme on an in-place reader (the
    /// Browser's reader mode, the Library's Read); nil elsewhere (the app's own surface).
    private var readingPalette: ReadingPalette? {
        guard readerMode else { return nil }
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
                return ChromePieces(state: drawn, width: proxy.size.width, screen: screen, underColor: underColor,
                                    focus: $focused, onSelect: shell.select, onExpand: expandTapped)
            }
                .opacity(dip)
                // Reduce Motion's full screen: outside the glass container, so the glass fades too.
                .opacity(reduceMotion && live.fullScreen ? 0 : 1)
                .animation(live.fullScreen ? Motion.fadeOut : Motion.fadeIn, value: reduceMotion && live.fullScreen)
                // Folding follows the finger frame by frame (`ChromeScroll.displayed`); every other change
                // is one step. A different destination (set last, so it wins when both change) is `snappy`.
                .animation(reduceMotion ? nil : Motion.standard, value: state.discrete)
                .animation(reduceMotion ? nil : Motion.snappy, value: destination)
        }
        .frame(height: ChromeMetrics.rowsHeight)
        .allowsHitTesting(!live.fullScreen)
        .accessibilityHidden(live.fullScreen)
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
        .onChange(of: isSearching, initial: true) { _, locked in scroll.isLocked = locked }
        .onChange(of: destination) { _, _ in focused = session?.isFocused == true }
        // Pages mode, VoiceOver, Edit and the start page's page arriving change the rule without a new screen.
        .onChange(of: conditions, initial: true) { _, new in scroll.conditions = new }
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

    /// The bubble's tap, the only way back to two rows by hand: they stay for a short scroll down, then fold again.
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
    /// A change during a dip joins it: the dip lands on the latest. Full screen is no form change
    /// (the host's own fade draws it), so it never starts a dip.
    private func liveChanged(to new: ChromeState) {
        pending = new
        guard reduceMotion, let current = shown else {
            shown = new
            return
        }
        guard Self.form(current) != Self.form(new), dip == 1 else { return }
        withAnimation(Motion.fadeOut) {
            dip = 0
        } completion: {
            shown = pending
            withAnimation(Motion.fadeIn) { dip = 1 }
        }
    }

    /// `state` without full screen: what a dip draws.
    private static func form(_ state: ChromeState) -> ChromeState {
        var form = state
        form.fullScreen = false
        return form
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
