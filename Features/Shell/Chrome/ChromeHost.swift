import SwiftData
import SwiftUI
import UIKit

/// The compact bottom chrome, one view above every destination (Reader, Library, Browser): two
/// rows expanded, one collapsed.
///
/// ```
/// expanded    [‹ ›][ address / Search Library          ]        row 1: the screen's own
///             [ Reader | Library | Browser ][▶][  ⋯  ]          row 2: where you are, play, menu
/// collapsed   [‹ ›][ address ][▶][icon][⋯]                      scrolled down: one row
/// searching   [ field                    ][icon][✕]             the keyboard is up (or its session open)
/// ```
///
/// Scrolling down collapses it (`ChromeState`); scrolling up, the icon's tap and a swipe up on the
/// row expand it (while searching, they lower the keyboard). The pill morphs into the icon (iOS 26: one `GlassEffectContainer`, `glassEffectID`;
/// Reduce Motion: a cross-fade; earlier iOS: the strip skin). The host never changes the size of
/// what is under it: screens reserve `ChromeMetrics.footprint` at the bottom and scroll under it.
///
/// It owns the field's focus (kept in sync with the session), the play /
/// pause button's state and the progress and toast overlays; each destination supplies its field,
/// arrows and ⋯ as a `ChromeScreen`.
struct ChromeHost: View {
    let browse: ChromeScreen
    let library: ChromeScreen

    @Environment(ShellState.self) private var shell
    @Environment(\.speechController) private var speech
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(FollowCenter.self) private var follow
    @Environment(PrepareCenter.self) private var preparedAudio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingAppearance) private var readingAppearance
    @Query(LibraryQueries.lastPlayed) private var lastPlayed: [Article]
    @FocusState private var focused: Bool
    @Namespace private var morph
    /// What is drawn: collapsed or not. Follows `wantsCollapsed` (animated, or through a dip under
    /// Reduce Motion).
    @State private var collapsed = false
    @State private var dip = 1.0

    private let skin = ChromeSkin.current

    /// The Reader is lit while the Reader sheet or Now Playing is up; otherwise the surface under.
    private var destination: ChromeDestination {
        if onReadingPage { .reader } else { shell.isInLibrary ? .library : .browse }
    }
    private var onReadingPage: Bool { shell.reader != nil || shell.isNowPlayingPresented }
    private var screen: ChromeScreen {
        if onReadingPage { readerScreen } else { shell.isInLibrary ? library : browse }
    }
    /// The Reader has no field or arrows: row 2 only, with the reading page's own ⋯ at its end.
    private var readerScreen: ChromeScreen {
        ChromeScreen(destination: .reader, more: AnyView(ReadingPageMoreButton(id: "chromeReaderMore", chrome: true)))
    }
    private var session: SearchSession? { screen.session }
    private var isSearching: Bool { session?.isActive == true }
    /// One row is drawn: collapsed, or searching.
    private var isOneRow: Bool { collapsed || isSearching }
    private var wantsCollapsed: Bool { shell.chrome.isScrolledDown && screen.editBar == nil && !onReadingPage
        && shell.pageReader == nil }

    /// What the page under the chrome is drawn in: the reading theme on the Reader, Now Playing and
    /// the Browser's in-place reader view; nil elsewhere (the app's own surface).
    private var readingPalette: ReadingPalette? {
        guard onReadingPage || shell.pageReader != nil else { return nil }
        return readingAppearance.palette(accent: AppAppearance.shared.accent)
    }
    /// Opaque, in the colour of what is under it: the reading theme, a web page's own background,
    /// or paper (the start page, the Library).
    private var fade: Color {
        if let readingPalette { return readingPalette.background }
        if destination == .browse, shell.web.hasPage, let page = shell.web.pageBackground { return Color(uiColor: page) }
        return Palette.paper
    }

    /// The page played last, while nothing is bound: the play button resumes it.
    private var resume: Article? { speech.nowPlaying == nil ? lastPlayed.first(where: \.isLive) : nil }
    private var hasPlay: Bool { speech.nowPlaying != nil || resume != nil }

    var body: some View {
        GeometryReader { proxy in
            let geometry = ChromeGeometry(.init(
                width: proxy.size.width, destination: destination, collapsed: collapsed, searching: isSearching,
                canGoBack: screen.canGoBack, canGoForward: screen.canGoForward, hasPlay: hasPlay))
            ZStack(alignment: .topLeading) {
                pieces(geometry)
            }
            .chromeGlassContainer()
            .frame(width: proxy.size.width, height: ChromeMetrics.footprint, alignment: .topLeading)
            .opacity(dip)
            .animation(reduceMotion ? nil : Motion.standard, value: geometry)
            .background(alignment: .bottom) { strip(geometry) }
            .overlay(alignment: .top) { overlays(geometry) }
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
        .onAppear {
            collapsed = wantsCollapsed
            focused = session?.isFocused == true
        }
        .onChange(of: wantsCollapsed) { _, wants in apply(wants) }
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
        .gesture(swipeUp, including: isOneRow ? .all : .subviews)
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
                .environment(\.chromeFieldCollapsed, g.isCollapsed)
                .overlay {
                    if destination == .browse {
                        LoadProgressLine(web: shell.web).frame(maxHeight: .infinity, alignment: .bottom).clipShape(Capsule())
                    }
                }
                .placed(fieldFrame)
        }
        if let play = g.play, let button = playButton {
            button.placed(play).transition(.opacity)
        }
        if g.isCollapsed {
            if let icon = g.icon {
                ChromeScreenIcon(destination: destination, action: iconTapped)
                    .chromeMorph("screen", in: morph)
                    .placed(icon)
                    .transition(.opacity)
            }
        } else if let pill = g.pill, screen.editBar == nil {
            ChromePill(lit: destination, reader: readerState, onSelect: select)
                .chromeMorph("screen", in: morph)
                .placed(pill)
                .transition(.opacity)
        }
        if let edit = screen.editBar, !g.isCollapsed {
            edit
                .frame(maxHeight: .infinity)
                .chromeSurface(Capsule())
                .placed(CGRect(x: ChromeMetrics.margin, y: g.more.minY,
                               width: g.more.maxX - ChromeMetrics.margin, height: ChromeMetrics.row2Height))
                .transition(.opacity)
        } else if isSearching {
            Button(action: screen.onCancel) { ChromeRoundLabel(symbol: Icons.close, label: Verbs.cancel) }
                .buttonStyle(.plain)
                .accessibilityLabel(Verbs.cancel)
                .accessibilityIdentifier(screen.cancelID)
                .placed(g.more)
        } else {
            screen.more.placed(g.more)
        }
    }

    /// ▶ / ⏸ beside the pill: pause or resume what is bound, or resume the page played last.
    private var playButton: ChromePlayButton? {
        if let now = speech.nowPlaying {
            return ChromePlayButton(state: speech.playState(of: .article(now.articleKey)), progress: {
                let doc = speech.document
                return doc.progress(atUTF16Offset: now.isFinished ? doc.utf16Length : speech.spokenUTF16Offset)
            }, action: speech.pressNowPlaying)
        }
        guard let article = resume else { return nil }
        let actions = libraryActions
        return ChromePlayButton(state: actions.playState(of: article), progress: {
            switch actions.progress(of: article) {
            case .partWay(let fraction, _): fraction
            case .finished: 1
            default: 0
            }
        }, action: { actions.play(article) })
    }

    private var readerState: PlayState? {
        if let now = speech.nowPlaying { return speech.playState(of: .article(now.articleKey)) }
        return resume == nil ? nil : .idle
    }

    private var libraryActions: LibraryActions {
        LibraryActions(library: libraryStore, speech: speech, shell: shell, follow: follow)
    }

    // MARK: - Strip skin (earlier iOS)

    /// The strip: one thick material behind the rows, as tall as the layout, down through the safe area.
    @ViewBuilder
    private func strip(_ g: ChromeGeometry) -> some View {
        if skin == .strip {
            let top = g.top - ChromeMetrics.topPadding
            Color.clear
                .frame(height: ChromeMetrics.footprint - top)
                .background(alignment: .bottom) { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
                .overlay(alignment: .top) { Divider() }
                .animation(reduceMotion ? nil : Motion.standard, value: g)
        } else if skin == .glass {
            // Glass floats on the content: the page's own background, opaque from the top of the
            // top piece down and fading in over `fadeHeight` above it, so page text never shows
            // through behind the pieces (the strip does that job on the fallback).
            let top = g.top - ChromeMetrics.topPadding
            // The reading sheets already keep their content clear of the chrome: no fade above it.
            let rise = onReadingPage ? 0 : ChromeMetrics.fadeHeight
            Color.clear
                .frame(height: ChromeMetrics.footprint - top)
                .background(alignment: .bottom) { fade.ignoresSafeArea(edges: .bottom) }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [fade.opacity(0), fade], startPoint: .top, endPoint: .bottom)
                        .frame(height: rise)
                        .offset(y: -rise)
                }
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : Motion.standard, value: g)
        }
    }

    // MARK: - Overlays

    /// The prepare progress and the toast sit on the layout's top edge, never in a row of their own.
    private func overlays(_ g: ChromeGeometry) -> some View {
        VStack(spacing: 0) {
            // The Reader and Now Playing float their own.
            if !onReadingPage {
                PrepareProgressEdge()
                ShellToastLayer()
            }
        }
        .offset(y: g.top - ChromeMetrics.topPadding)
        .animation(reduceMotion ? nil : Motion.standard, value: g)
    }

    // MARK: - Actions

    private func select(_ target: ChromeDestination) {
        // The lit Reader is where you already are.
        guard target != .reader || destination != .reader else { return }
        switch target {
        case .library: shell.openLibrary()
        case .browse: shell.showBrowser()
        case .reader: openReader()
        }
    }

    /// The Reader segment, until the Reader is a screen of its own: what is playing opens as Now
    /// Playing, else the page played last opens in the Reader; with neither, a note.
    private func openReader() {
        if speech.nowPlaying != nil {
            shell.showNowPlaying()
        } else if let article = resume {
            libraryActions.open(article)
        } else {
            shell.showToast(ShellToast(message: String(localized: "Nothing to read yet. Open a page and tap Reader."),
                                       systemImage: Icons.reader))
        }
    }

    /// The icon is a swipe up: back to two rows. While searching the row stays one, so it lowers the keyboard.
    private func iconTapped() {
        if let session, session.isActive {
            session.lowerKeyboard()
        } else {
            shell.chrome.expand()
        }
    }

    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                guard isOneRow, value.translation.height < -24,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                iconTapped()
            }
    }

    /// Applies a new collapsed state: spring (the geometry animates it), or under Reduce Motion a
    /// dip: fade out, swap, fade in.
    private func apply(_ wants: Bool) {
        guard reduceMotion else {
            collapsed = wants
            return
        }
        withAnimation(Motion.fadeOut) {
            dip = 0
        } completion: {
            collapsed = wants
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

extension ChromeGeometry {
    /// The top edge of the highest piece.
    var top: CGFloat {
        [field?.minY, back?.minY, forward?.minY, pill?.minY, play?.minY, icon?.minY, more.minY]
            .compactMap { $0 }.min() ?? 0
    }
}
