import SwiftUI
import UIKit

/// The compact bottom chrome, one view above every destination (Reader, Library, Browser): two
/// rows expanded, one collapsed, none in the Reader's full screen. `ChromeState` says what is
/// drawn and `ChromeGeometry` where; this view only wires them to the app.
///
/// ```
/// expanded    [‹ ›][ address / Search Library          ]        row 1: the screen's own (not the Reader's)
///             [ Reader | Library | Browser ][▶][  ⋯  ]          row 2: where you are, play, menu
/// collapsed   [‹ ›][ address ][▶][icon][⋯]                      scrolled down: one row (the Reader: its title chip)
/// keyboard    [ field                    ][icon][✕]             the keyboard is up (or its session open)
/// full screen (nothing)                                         the Reader's middle tap
/// ```
///
/// Scrolling down collapses it (`ChromeScroll`); the icon's tap, a swipe up on the row and the top
/// of the text expand it (while searching, they lower the keyboard), and scrolling up does where
/// the screen allows it (`ReaderChromeScroll`). The pill morphs into the icon (iOS 26: one
/// `GlassEffectContainer`, `glassEffectID`; Reduce Motion: a cross-fade; earlier iOS: the strip
/// skin). The host never changes the size of what is under it: screens reserve
/// `ChromeMetrics.footprint` (the Reader `row2Footprint`) at the bottom and scroll under it.
///
/// It owns the field's focus (kept in sync with the session), the play / pause button's state and
/// the progress and toast overlays; each destination supplies its field, arrows and ⋯ as a
/// `ChromeScreen`.
struct ChromeHost: View {
    let browse: ChromeScreen
    let library: ChromeScreen

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingAppearance) private var readingAppearance
    private let playback = ChromePlayback()
    @FocusState private var focused: Bool
    @Namespace private var morph
    /// Reduce Motion: the old presence, drawn while the chrome fades out before the new one fades in.
    @State private var held: ChromePresence?
    @State private var dip = 1.0

    private let skin = ChromeSkin.current

    private var destination: ChromeDestination { shell.chromeDestination }
    private var screen: ChromeScreen {
        switch destination {
        case .reader: readerScreen
        case .library: library
        case .browse: browse
        }
    }
    /// The Reader has no arrows or search: its field slot is the title chip, and its ⋯ is the reading
    /// page's own menu.
    private var readerScreen: ChromeScreen {
        let (title, detail) = readerTitle
        return ChromeScreen(
            field: { _ in AnyView(ChromeTitleChip(title: title, detail: detail, action: iconTapped)) },
            more: AnyView(ReadingPageMoreButton(id: "chromeReaderMore", chrome: true)))
    }
    /// What the Reader names the page by: Now Playing's page, else the Reader's, and its source.
    private var readerTitle: (title: String, detail: String) {
        if shell.isNowPlayingPresented, let now = speech.nowPlaying {
            return (now.lineOne, now.source == now.lineOne ? "" : now.source)
        }
        guard let article = shell.readerArticle else { return ("", "") }
        let title = ArticleRowTitle.lineOne(title: article.title, source: article.sourceLabel,
                                            address: article.origin.canonicalURL)
        return (title, article.sourceLabel == title ? "" : article.sourceLabel)
    }
    private var session: SearchSession? { screen.session }
    private var isSearching: Bool { session?.isActive == true }

    private var state: ChromeState {
        ChromeState(destination: destination, presence: held ?? shell.chrome.presence, played: playback.isAvailable, canGoBack: screen.canGoBack,
                    canGoForward: screen.canGoForward, keyboard: isSearching, readerMode: destination == .browse && shell.pageReader != nil,
                    editing: screen.editBar != nil)
    }

    /// What the page under the chrome is drawn in: the reading theme on the Reader, Now Playing and
    /// the Browser's in-place reader view; nil elsewhere (the app's own surface).
    private var readingPalette: ReadingPalette? {
        guard destination == .reader || shell.pageReader != nil else { return nil }
        return readingAppearance.palette(accent: AppAppearance.shared.accent)
    }
    /// Opaque, in the colour of what is under it: the reading theme, a web page's own background,
    /// or paper (the start page, the search layer, the Library).
    private var underColor: Color {
        if let readingPalette { return readingPalette.background }
        if destination == .browse, shell.web.hasPage, !isSearching, let page = shell.web.pageBackground {
            return Color(uiColor: page)
        }
        return Palette.paper
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = ChromeGeometry(width: proxy.size.width, state: state)
            ZStack(alignment: .topLeading) {
                pieces(geometry)
            }
            .chromeGlassContainer()
            .frame(width: proxy.size.width, height: ChromeMetrics.footprint, alignment: .topLeading)
            .opacity(dip)
            .background(alignment: .bottom) { ChromeBackdrop(fade: geometry.fade, skin: skin, underColor: underColor) }
            .overlay(alignment: .top) { overlays(geometry) }
            // Collapsing and expanding are `standard`; a different destination (set last, so it
            // wins when both change) is `snappy`. The backdrop and overlays come and go with it.
            .animation(reduceMotion ? nil : Motion.standard, value: geometry)
            .animation(reduceMotion ? nil : Motion.snappy, value: destination)
        }
        .frame(height: ChromeMetrics.footprint)
        .environment(\.chromeSkin, skin)
        // The pieces are fixed-height capsules: their text stops growing here, and the large
        // content viewer shows what the glyphs are.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .readingSurface(readingPalette)
        .tint(Palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chromeHost")
        .onAppear { focused = session?.isFocused == true }
        .onChange(of: shell.chrome.presence) { old, _ in fadeThrough(from: old) }
        .onChange(of: destination) { _, _ in
            shell.chrome.reset()
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
        .gesture(swipeUp, including: state.rows == .one ? .all : .subviews)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func pieces(_ g: ChromeGeometry) -> some View {
        // Row 1 (expanded) or the left of the one row.
        if let nav = g.navigation {
            ChromeNavigation(canGoBack: screen.canGoBack, showsForward: g.forward != nil, backID: screen.backID,
                             forwardID: screen.forwardID, onBack: screen.onBack, onForward: screen.onForward)
                .placed(nav)
                .transition(.opacity)
        }
        if let fieldFrame = g.field {
            screen.field($focused)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bandField")
                .environment(\.chromeFieldHeight, fieldFrame.height)
                .environment(\.chromeFieldCollapsed, g.rows == .one)
                .overlay {
                    if destination == .browse {
                        LoadProgressLine(web: shell.web).frame(maxHeight: .infinity, alignment: .bottom).clipShape(Capsule())
                    }
                }
                .placed(fieldFrame)
        }
        if let play = g.play, let button = playback.button {
            button.placed(play).transition(.opacity)
        }
        if let icon = g.icon {
            ChromeScreenIcon(destination: destination, action: iconTapped)
                .chromeMorph("screen", in: morph)
                .placed(icon)
                .transition(.opacity)
        } else if let pill = g.pill {
            ChromePill(lit: destination, hasReader: playback.isAvailable, onSelect: playback.select)
                .chromeMorph("screen", in: morph)
                .placed(pill)
                .transition(.opacity)
        }
        if let bar = g.editBar, let edit = screen.editBar {
            edit
                .frame(maxHeight: .infinity)
                .chromeSurface(Capsule())
                .placed(bar)
                .transition(.opacity)
        }
        if let more = g.more {
            if isSearching {
                Button(action: screen.onCancel) { ChromeRoundLabel(symbol: Icons.close, label: Verbs.cancel) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Verbs.cancel)
                    .accessibilityIdentifier(screen.cancelID)
                    .placed(more)
            } else {
                screen.more.placed(more)
            }
        }
    }

    // MARK: - Overlays

    /// The prepare progress and the toast sit on the layout's top edge, never in a row of their own.
    @ViewBuilder
    private func overlays(_ g: ChromeGeometry) -> some View {
        if let top = g.overlayTop {
            VStack(spacing: 0) {
                PrepareProgressEdge()
                ShellToastLayer()
            }
            .offset(y: top)
            .transition(.opacity)
        }
    }

    // MARK: - Actions

    /// The icon, the title chip and a swipe up on the row: back to two rows. While searching the
    /// row stays one, so it lowers the keyboard.
    private func iconTapped() {
        if let session, session.isActive {
            session.lowerKeyboard()
        } else {
            shell.chrome.expand()
        }
    }

    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: ChromeScroll.swipeStart)
            .onEnded { value in
                guard state.rows == .one, ChromeScroll.isSwipeUp(value.translation) else { return }
                iconTapped()
            }
    }

    /// A new presence is drawn by the geometry animating to it; under Reduce Motion by a dip: the
    /// old one fades out, the new one fades in.
    private func fadeThrough(from old: ChromePresence) {
        guard reduceMotion else { return }
        held = held ?? old
        withAnimation(Motion.fadeOut) {
            dip = 0
        } completion: {
            held = nil
            withAnimation(Motion.fadeIn) { dip = 1 }
        }
    }

    private static func selectAllInFocusedField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }
}

private extension View {
    /// Fixed `rect` in the host's top-leading box.
    func placed(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
