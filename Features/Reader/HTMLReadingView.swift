import Foundation
import SwiftUI
import WebKit

/// The page's title and source line, drawn at the top of the text (part of the page, so it
/// scrolls with it; not a listen block, so it never shifts paragraph indices).
struct ReaderHeading: Equatable {
    /// nil: the page has none, and the heading is its source line alone.
    var title: String?
    /// The source and the length, as separate parts (["example.org", "9 min"]): spans set apart
    /// by space, the first in secondary ink, the rest in tertiary (like `DetailLine`).
    var detail: [String]
}

/// A native view at the top of the text that scrolls with it, in place of the HTML title and
/// source line (Now Playing's title card). `id` says when it changed: the hosted view is only
/// replaced then.
struct ReadingTopView: Equatable {
    let id: AnyHashable
    let view: AnyView

    static func == (a: ReadingTopView, b: ReadingTopView) -> Bool { a.id == b.id }
}

/// Lets the owner read where the text is scrolled to (the Reader hands it to Now Playing, D2).
@MainActor
final class ReadingScrollHandle {
    fileprivate weak var coordinator: HTMLReadingWebView.Coordinator?

    /// Where the text is scrolled to, as `Coordinator.handOver`. Nil before the page is up.
    var handOver: ReadingHandOver? { coordinator?.handOver }
}

/// Renders an article's reading HTML in the reading style (`ReadingStyle`: the reading theme's
/// colours from `readingPalette`, the typeface, text size and line spacing from the
/// `readingAppearance` store, all changed live), the same for the Reader and Now Playing, with
/// tap-to-start and, in Now Playing, following the audio:
/// - `follows`: the text keeps the spoken sentence near the middle (the paragraph, before its
///   sentence is known): it opens there, goes there on each new `activeParagraphIndex`, and,
///   in a paragraph too long to stay in view, again when the spoken sentence leaves the visible
///   text. Moves run on the `Motion.standard` spring (a jump under Reduce Motion). A finger drag
///   turns it off (`onUserScroll`); the owner turns it back on (Jump to Audio), which goes to the
///   sentence.
/// - `sentence`: the spoken sentence is underlined (CSS Custom Highlight, iOS 17.2+; earlier
///   systems show the paragraph's highlight alone).
/// - `opensAtSentence` (the Reader, at a saved listening spot): the text opens with `sentence`
///   in the middle, and keeps it there through layout changes until the text is dragged.
/// Without `follows` (the Reader) the text never scrolls by itself after that, except to follow
/// a scrub.
/// In a reading sheet (`readingChrome` in the environment) the text runs under the sheet's bars,
/// its scroll insets their heights, and drags and taps on it drive full screen (see
/// `HTMLReadingView+Taps.swift`); in full screen the spoken sentence centres in the whole screen.
/// There the reading appearance's Pages layout shows it a page of whole lines at a time
/// (`HTMLReadingView+Pages.swift`), with the page and `pageTimeLeft` in a footer; elsewhere it
/// scrolls (`HTMLReadingView+Scroll.swift`). The coordinator decides what the text shows (its
/// `hold`, the spoken sentence, a scrub, a link); the layout (`ReadingTextLayout`) puts it on
/// screen.
/// Links open through `onOpenLink`.
/// Indices follow `ListenHTMLBlocks` leaf elements (same as speech).
struct HTMLReadingView: View {
    let html: String
    /// The title and source line on top of the text (the Reader); with a `topView`, only the
    /// title it shows, so the text's own leading heading saying the same is hidden.
    var heading: ReaderHeading? = nil
    /// A native view on top of the text instead (the player's title card).
    var topView: ReadingTopView? = nil
    let activeParagraphIndex: Int?
    var sentence: ReaderSentence? = nil
    /// The word being spoken (its first character): following in Pages, the page turns when it
    /// reaches the next one.
    var spokenWord: ReadingPages.Spot? = nil
    /// Taps only jump playback while this is on (scrolling / casual taps never skip).
    var jumpMode: Bool = false
    /// Scroll a paragraph into view: following a scrub.
    var scrollRequest: ReaderScrollRequest? = nil
    var follows = false
    /// Open with `sentence` in the middle of the text, instead of at the top.
    var opensAtSentence = false
    /// Where the text opens (another page's `handOver`: its top, or the same line at the same place
    /// on screen), instead of the top or the spoken sentence.
    var opensAt: ReadingHandOver? = nil
    var scrollHandle: ReadingScrollHandle? = nil
    var onUserScroll: () -> Void = {}
    /// A link on the page was tapped (the reading view never follows one).
    var onOpenLink: (URL) -> Void = { _ in }
    /// Pages mode's footer: the time left from a page's first character (its listen paragraph and
    /// the UTF-16 offset in it), "2 min left" ("2 min left in chapter" for a chapter); nil shows the
    /// page alone.
    var pageTimeLeft: (_ paragraph: Int, _ offset: Int) -> String? = { _, _ in nil }
    /// *Play from Here* on a text selection (C109): its listen paragraph and the offset in it;
    /// nil offers none.
    var onPlaySelection: ((_ paragraph: Int, _ offset: Int) -> Void)? = nil
    let onTapParagraph: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readingPalette) private var reading
    @Environment(\.readingAppearance) private var appearance
    @Environment(\.readingChrome) private var chrome
    @State private var pages = ReadingPages()

    private var palette: ReadingPalette { reading ?? .app }

    var body: some View {
        // Pages only in a reading sheet: Follow's preview has no bars to page under.
        let paged = chrome != nil && appearance.layout == .pages
        let look = ReadingStyle.Look(colors: ReadingStyle.Colors(palette, scheme: colorScheme), font: appearance.font,
                                     lineSpacing: appearance.lineSpacing, textScale: appearance.textScale)
        let sizes = ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory:
            UIContentSizeCategory(dynamicTypeSize)))
        HTMLReadingWebView(
            html: html,
            look: look,
            heading: heading,
            topView: topView,
            activeParagraphIndex: activeParagraphIndex,
            sentence: sentence,
            spokenWord: spokenWord,
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: follows,
            opensAtSentence: opensAtSentence,
            opensAt: opensAt,
            scrollHandle: scrollHandle,
            chrome: chrome,
            fullScreen: chrome?.hidden == true,
            textInsets: chrome?.insets ?? ReaderTextInsets(),
            pages: paged ? pages : nil,
            pageFooter: paged ? (chrome?.homeIndicator ?? 0) + (chrome?.pageFooter ?? 0) : 0,
            sizes: sizes,
            animates: !reduceMotion,
            onUserScroll: onUserScroll,
            onOpenLink: onOpenLink,
            onPlaySelection: onPlaySelection,
            onTapParagraph: onTapParagraph
        )
        .background(palette.background)
        .modifier(ReadingPagesCard(active: paged, overview: chrome?.hidden == false, insets: chrome?.insets ?? ReaderTextInsets(),
                                   cardHeight: paged ? pages.cardHeight : 0))
        .overlay {
            if paged { ReadingPageFrame(pages: pages, palette: palette, timeLeft: pageTimeLeft) }
        }
        .overlay(alignment: .top) {
            // Scroll's full screen: the text's top edge fades into the page over a line's height,
            // so a line scrolled part-way past it never shows cut (Pages shows whole lines). The
            // bars cover it when they show.
            if chrome != nil, !paged {
                LinearGradient(colors: [palette.background, palette.background.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: look.lineHeight(sizes))
                    .opacity(chrome?.hidden == true ? 1 : 0)
                    .animation(Motion.standard, value: chrome?.hidden == true)
                    .allowsHitTesting(false)
            }
        }
    }
}

private extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}

struct HTMLReadingWebView: UIViewRepresentable {
    let html: String
    var look = ReadingStyle.Look.standard
    var heading: ReaderHeading?
    var topView: ReadingTopView?
    let activeParagraphIndex: Int?
    var sentence: ReaderSentence?
    var spokenWord: ReadingPages.Spot?
    let jumpMode: Bool
    var scrollRequest: ReaderScrollRequest? = nil
    var follows = false
    var opensAtSentence = false
    var opensAt: ReadingHandOver?
    var scrollHandle: ReadingScrollHandle?
    /// The reading sheet's bars; nil outside one (no full screen, no page turns).
    var chrome: ReadingChrome?
    /// The bars are hidden: a pull at the top shows them instead of pulling the sheet.
    var fullScreen = false
    /// Room left above / below the text for the bars drawn over it.
    var textInsets = ReaderTextInsets()
    /// Pages mode's state; nil in Scroll mode.
    var pages: ReadingPages?
    /// Pages mode: the room under the pages (the footer and the home indicator's inset).
    var pageFooter: CGFloat = 0
    var sizes = ReadingStyle.Sizes()
    var animates = true
    var onUserScroll: () -> Void = {}
    var onOpenLink: (URL) -> Void = { _ in }
    var onPlaySelection: ((_ paragraph: Int, _ offset: Int) -> Void)?
    let onTapParagraph: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapParagraph: onTapParagraph)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(coordinator: context.coordinator)
        let c = context.coordinator
        c.setLayout(pages: pages, footer: pageFooter)
        c.setTextInsets(textInsets)
        (c.layout as? PagesTextLayout)?.setOverview(!fullScreen)
        c.follows = follows
        c.opensAtSentence = opensAtSentence
        c.sizes = sizes
        c.look = look
        c.setTopView(topView)
        scrollHandle?.coordinator = c
        c.load(html: html, heading: heading, opensAt: opensAt)
        return webView
    }

    /// The reader's web view, wired to `coordinator` (bridge, navigation, drags).
    ///
    /// Article HTML is untrusted: Readability keeps inline handlers (`onerror`, `onclick`) and
    /// `javascript:` links, and they must not run next to `readerBridge`. Content JavaScript is
    /// off; the bootstrap `WKUserScript`, the listeners it installs and the coordinator's
    /// `evaluateJavaScript` calls still run.
    static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration.appWebView(pageScripts: false)
        let userContent = config.userContentController
        userContent.add(coordinator, name: "readerBridge")
        userContent.addUserScript(WKUserScript(
            source: Self.bootstrapJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = ReadingWebView(frame: .zero, configuration: config)
        webView.canPlayFromHere = { [weak coordinator] in coordinator?.onPlaySelection != nil }
        webView.onPlayFromHere = { [weak coordinator] in coordinator?.playFromSelection() }
        webView.onLayout = { [weak coordinator] in coordinator?.layoutTopView() }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The scroll view's content inset (see `setTextInsets`) keeps the first / last lines clear
        // of chrome drawn over the text. Native insets, not CSS padding: article HTML (e.g.
        // Wikipedia's styles) can't override them.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        coordinator.observeDragging(webView.scrollView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let c = context.coordinator
        c.onTapParagraph = onTapParagraph
        c.onPlaySelection = onPlaySelection
        c.onUserScroll = onUserScroll
        c.onOpenLink = onOpenLink
        c.chrome = chrome
        // In full screen a pull at the top only rubber-bands (and brings the bars back); a drag
        // in progress keeps the hand-off it began with (`ScrollPullHandoff`).
        c.pullHandoff.handoff = fullScreen ? nil : context.environment.sheetPullHandoff
        c.animates = animates
        scrollHandle?.coordinator = c
        c.setLayout(pages: pages, footer: pageFooter)
        c.setTextInsets(textInsets)
        (c.layout as? PagesTextLayout)?.setOverview(!fullScreen)
        c.setTopView(topView)
        if c.lastHTML != html || c.lastHeading != heading {
            c.load(html: html, heading: heading)
        }
        c.setSizes(sizes)
        c.setLook(look)
        // The sentence first: a new paragraph goes straight to its sentence.
        c.setSentence(sentence)
        c.setActiveParagraph(activeParagraphIndex)
        c.setSpokenWord(spokenWord)
        c.setJumpMode(jumpMode)
        c.setFollows(follows)
        c.scroll(scrollRequest)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTapParagraph: (Int) -> Void
        var onPlaySelection: ((_ paragraph: Int, _ offset: Int) -> Void)?

        /// *Play from Here* (C109): the selection's start, then the owner plays from its sentence.
        func playFromSelection() {
            guard let webView, let onPlaySelection else { return }
            webView.evaluateJavaScript("window.__readerSelectionSpot()") { result, _ in
                guard let spot = result as? [Int], spot.count == 2 else { return }
                onPlaySelection(spot[0], spot[1])
            }
        }
        var onUserScroll: () -> Void = {}
        var onOpenLink: (URL) -> Void = { _ in }
        weak var chrome: ReadingChrome?
        weak var webView: WKWebView?
        var lastHTML: String = ""
        var lastHeading: ReaderHeading?
        var sizes = ReadingStyle.Sizes()
        private var sentSizes: ReadingStyle.Sizes?
        /// The colours, typeface, text size and spacing. Set before the first load by `makeUIView`,
        /// then through `setLook`.
        var look = ReadingStyle.Look.standard
        private var sentLook: ReadingStyle.Look?
        var animates = true
        /// Following the audio (Now Playing). Set before the first load by `makeUIView`.
        var follows = false
        /// Opens with the sentence in the middle (the Reader's saved spot). Set before the first
        /// load by `makeUIView`.
        var opensAtSentence = false
        private(set) var loaded = false
        private var pendingActive: Int?
        /// Highlight index the page last received; nil = nothing sent since the page loaded.
        /// SwiftUI calls `updateUIView` far more often than the paragraph changes, so only a new
        /// index crosses into the WebContent process.
        private var sentActive: Int??
        private var pendingSentence: ReaderSentence?
        private var sentSentence: ReaderSentence??
        private(set) var jumpMode = false
        private var lastSentJumpMode: Bool?
        private var lastScrollToken: Int?
        private(set) var textInsets = ReaderTextInsets()
        private var sentInsets: ReaderTextInsets?
        /// Scroll or Pages (`setLayout`): it puts on screen what this coordinator decides to show.
        private(set) lazy var layout: ReadingTextLayout = ScrollTextLayout(host: self)

        /// Where the app keeps the text until the user moves it (a drag, a page turn, a link).
        enum Hold: Equatable {
            /// A fresh page: its top, the first line just below the top bar.
            case top
            /// Another page's place (D2), until the layout has put it on screen.
            case handOver(ReadingHandOver)
            /// The spoken sentence in the middle (the Reader's saved spot).
            case spoken
            /// A paragraph scrubbed to, until the layout has shown it.
            case paragraph(Int)
        }
        /// Nil: the reader's own place, which a new layout keeps on screen.
        private(set) var hold: Hold?

        init(onTapParagraph: @escaping (Int) -> Void) {
            self.onTapParagraph = onTapParagraph
        }

        /// Shows `html`. `opensAt` is where this load opens (the D2 handoff); any other load opens
        /// at the top, or at the spoken sentence when following or `opensAtSentence`.
        func load(html: String, heading: ReaderHeading? = nil, opensAt: ReadingHandOver? = nil) {
            lastHTML = html
            lastHeading = heading
            loaded = false
            sentActive = nil
            sentSentence = nil
            sentSizes = sizes
            sentLook = look
            loadGeneration += 1
            hold = opensAt.map(Hold.handOver) ?? (opensAtSentence ? .spoken : .top)
            spokenShown = nil
            textTop = 0
            reflowing = false
            queuedReflow = []
            layout.reset()
            let top = topHost == nil ? nil : sentTopHeight ?? 0
            pageTopHeight = top
            webView?.loadHTMLString(Self.wrap(html, heading: heading, top: top, sizes: sizes, look: look), baseURL: nil)
        }

        /// Scroll ↔ Pages (`pages`: Pages mode's state, nil in Scroll mode), live: the line at the
        /// top of the reading area stays there. A load in flight opens in the new mode.
        func setLayout(pages model: ReadingPages?, footer: CGFloat) {
            if let pages = layout as? PagesTextLayout, pages.model === model { return pages.setFooter(footer) }
            guard model != nil || layout is PagesTextLayout else { return }
            layout.deactivate()
            if case .handOver = hold { hold = nil }
            webView?.scrollView.showsVerticalScrollIndicator = model == nil
            if let model {
                let pages = PagesTextLayout(host: self, model: model, footer: footer)
                layout = pages
                if loaded { pages.activate() }
            } else {
                layout = ScrollTextLayout(host: self)
                if loaded { reapplyInsets() }
            }
        }

        // MARK: The top view (the title card)

        private var topHost: UIHostingController<AnyView>?
        private var topID: AnyHashable?
        /// The top view's height, measured; nil = not yet.
        private var sentTopHeight: CGFloat?
        /// The height the page's slot has (or will have, once the change in flight lands).
        private var pageTopHeight: CGFloat?
        private var measuredTopWidth: CGFloat = 0

        /// How far the article text starts below the top of the page's content (the title and
        /// source line, or the title card's slot); 0 with nothing above it. Measured on load and
        /// whenever what's above changes size.
        private(set) var textTop: CGFloat = 0

        /// The scroll position handed to another page (the Reader's, to Now Playing). At the top
        /// (the text's first line not yet scrolled above the top of the reading area) it is
        /// `.top`. Scrolled into the text, it is how far the top of the article text sits above
        /// the top of the window: that counts what is above the text on the page (the title, or
        /// the title card, which differ in height) and where the web view sits on screen, so the
        /// page that opens at it shows the same line at the same place on screen. Nil while the web view is off screen.
        var handOver: ReadingHandOver? {
            guard let webView, webView.window != nil else { return nil }
            let sv = webView.scrollView
            // Half a point of slack: a page at its top can sit a fraction off it.
            guard sv.contentOffset.y + sv.contentInset.top > textTop + 0.5 else { return .top }
            return .text(offset: sv.contentOffset.y - textTop - viewportTop(of: webView))
        }

        /// The document y of the top of the reading area that opens at `handOver` (scrolled into
        /// the text).
        func documentY(of handOver: CGFloat, in webView: WKWebView) -> CGFloat {
            textTop + max(0, viewportTop(of: webView) + webView.scrollView.contentInset.top + handOver)
        }

        /// The window y of the top of the web view's scroll view (its viewport).
        func viewportTop(of webView: WKWebView) -> CGFloat {
            let sv = webView.scrollView
            return sv.convert(CGPoint(x: 0, y: sv.bounds.minY), to: nil).y
        }

        func setTopView(_ top: ReadingTopView?) {
            guard top?.id != topID else { return }
            topID = top?.id
            if let top {
                if let topHost {
                    topHost.rootView = top.view
                } else {
                    let host = UIHostingController(rootView: top.view)
                    host.view.backgroundColor = .clear
                    host.safeAreaRegions = []
                    // Its text grows with Dynamic Type: measure it again.
                    host.view.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
                        [weak self] (_: UIView, _: UITraitCollection) in
                        self?.measuredTopWidth = 0
                        self?.layoutTopView()
                    }
                    webView?.scrollView.addSubview(host.view)
                    topHost = host
                }
            } else {
                topHost?.view.removeFromSuperview()
                topHost = nil
            }
            measuredTopWidth = 0
            layoutTopView()
        }

        /// Pages mode's column box starts this far down (C107): the top view sits on its slot there.
        var topViewY: CGFloat = 0 {
            didSet { if oldValue != topViewY { topHost?.view.frame.origin.y = Spacing.xs + topViewY } }
        }

        /// Sizes the top view to the page's width (inset by `Spacing.m`, at the body's top padding)
        /// and makes the page's slot under it as tall.
        func layoutTopView() {
            layout.viewportLaidOut()
            guard let webView, let host = topHost else { return }
            let width = webView.bounds.width - 2 * Spacing.m
            guard width > 0 else { return }
            if host.view.superview == nil { webView.scrollView.addSubview(host.view) }
            if width != measuredTopWidth {
                measuredTopWidth = width
                let height = ceil(host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                host.view.frame = CGRect(x: Spacing.m, y: Spacing.xs + topViewY, width: width, height: height)
                if height != sentTopHeight {
                    sentTopHeight = height
                    sendTopHeight()
                }
            }
        }

        /// Gives the page's slot the top view's height, keeping the line being read in place.
        private func sendTopHeight() {
            guard loaded, let height = sentTopHeight, height != pageTopHeight else { return }
            // What is above the text moves the text by as much, and an offset the layout is still
            // settling works it out from `textTop` on the next frame: say so before the page has
            // answered (it confirms it, see `reflow`).
            if let old = pageTopHeight, layout.isSettling { textTop += height - old }
            pageTopHeight = height
            reflow(Self.topHeightScript(height))
        }

        private static func topHeightScript(_ height: CGFloat) -> String {
            "var t = document.querySelector('.reader-top'); if (t) t.style.height = '\(Int(height))px';"
        }

        /// Measures `textTop` (after any style change queued before it), then runs `then`.
        private func measureTextTop(then: (() -> Void)? = nil) {
            guard let webView else { return }
            let generation = loadGeneration
            webView.evaluateJavaScript("window.__readerTextTop()") { [weak self] result, _ in
                guard let self, generation == self.loadGeneration else { return }
                self.textTop = CGFloat((result as? Double) ?? 0)
                then?()
            }
        }

        /// Asks the page where something sits (`js` answers [document top, height, the text's
        /// top]) and hands the top and height to `then`, for the load it was asked on.
        func locate(_ js: String, then: @escaping (_ top: CGFloat, _ height: CGFloat) -> Void) {
            guard let webView else { return }
            let generation = loadGeneration
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, generation == loadGeneration, let rect = result as? [Double], rect.count == 3 else { return }
                textTop = CGFloat(rect[2])
                then(CGFloat(rect[0]), CGFloat(rect[1]))
            }
        }

        /// Counts loads, so an answer from the page (and a layout's timers) only acts on the page
        /// it was asked about.
        private(set) var loadGeneration = 0

        // MARK: Putting the hold on screen

        /// The page opened, or laid out again (a reflow, Pages measured): the hold goes back on
        /// screen. A hand-over is the layout's to place; the spoken sentence goes to the middle
        /// while the text goes there.
        func placeHold() {
            switch hold {
            case .handOver:
                break
            case .paragraph(let index):
                showParagraph(index)
            case .top, .spoken, nil:
                if goesToSpoken { goToSpoken(.jump, explicit: true) }
            }
        }

        /// The layout has put a hand-over on screen: the place is the reader's from now on.
        func handOverPlaced() {
            if case .handOver = hold { hold = nil }
        }

        /// The character a new pagination keeps on screen for the hold (the spoken sentence's
        /// first, or a scrubbed paragraph's); nil: the reader's own place.
        var heldSpot: ReadingPages.Spot? {
            switch hold {
            case .paragraph(let index): ReadingPages.Spot(paragraph: index, offset: 0)
            case .handOver: nil
            case .top, .spoken, nil: goesToSpoken ? spokenSpot.map(ReadingPages.Spot.init) : nil
            }
        }

        /// The paragraph scrubbed to, in the middle; the hold goes once the layout has shown it.
        private func showParagraph(_ index: Int) {
            if let pages = layout as? PagesTextLayout {
                hold = nil
                return pages.show(spot: ReadingPages.Spot(paragraph: index, offset: 0))
            }
            locate("window.__readerSpokenRect(\(index), null, null)") { [weak self] top, height in
                guard let self, hold == .paragraph(index) else { return }
                if layout.show(top: top, height: height, .centre(.jump)) { hold = nil }
            }
        }

        // MARK: Reflow (Dynamic Type, the title card) keeps the line being read

        private var reflowing = false
        private var queuedReflow: [String] = []

        /// Runs `change` (a style change that reflows the page) keeping the line being read: the
        /// reading anchor (the paragraph and the UTF-16 offset of the first character on the line
        /// at the top of the reading area, `layout.reflowAnchor()`), measured before and after the
        /// change in one go. The layout keeps it on screen, then the hold goes back. Changes run
        /// one at a time, so each anchor is measured on the page as the last one left it.
        private func reflow(_ change: String) {
            guard loaded, let webView else { return }
            guard !reflowing else { return queuedReflow.append(change) }
            reflowing = true
            let generation = loadGeneration
            let anchor = layout.reflowAnchor()
            let js = "(function(){ var a = window.__readerAnchor(\(Double(anchor.y))); \(change)"
                + " return window.__readerAnchorMoved(a); })();"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, generation == loadGeneration else { return }
                reflowing = false
                if let moved = result as? [Double], moved.count == 4 {
                    textTop = CGFloat(moved[3])
                    layout.reflowed(ReadingReflow(lineBefore: moved[0], lineAfter: moved[1],
                                                  textTopBefore: moved[2], textTopAfter: moved[3]), atTop: anchor.atTop)
                }
                if !queuedReflow.isEmpty {
                    let next = queuedReflow.joined(separator: " ")
                    queuedReflow = []
                    reflow(next)
                }
            }
        }

        /// Keeps the scroll view's top / bottom inset equal to the chrome over the text, so the
        /// first line starts below it and the last one scrolls clear of it.
        func setTextInsets(_ insets: ReaderTextInsets) {
            textInsets = insets
            guard insets != sentInsets, webView != nil else { return }
            sentInsets = insets
            layout.setInsets(insets)
        }

        /// The insets again, for a new layout or a new viewport.
        func reapplyInsets() {
            sentInsets = nil
            setTextInsets(textInsets)
        }

        func setSizes(_ sizes: ReadingStyle.Sizes) {
            self.sizes = sizes
            guard loaded, sizes != sentSizes else { return }
            sentSizes = sizes
            reflow(ReadingStyle.variablesScript(sizes, look))
        }

        /// A new reading appearance, live: colours alone repaint; a typeface, size or spacing
        /// change reflows the text, keeping the line on screen where it was.
        func setLook(_ look: ReadingStyle.Look) {
            let old = sentLook
            self.look = look
            guard loaded, look != old else { return }
            sentLook = look
            (layout as? PagesTextLayout)?.lookChanged()
            let script = ReadingStyle.variablesScript(sizes, look)
            if let old, old.font == look.font, old.lineSpacing == look.lineSpacing, old.textScale == look.textScale {
                webView?.evaluateJavaScript(script, completionHandler: nil)
            } else {
                reflow(script)
            }
        }

        /// Hands a pull at the top of the text to the sheet around it (`SheetPullHandoff`).
        let pullHandoff = ScrollPullHandoff()

        /// Notes a finger drag through the scroll view's pan (WebKit owns its delegate;
        /// programmatic scrolls never reach it): the user took over the text, and its movement
        /// goes to the bars (none in jump mode); let go, the layout settles it (Pages snaps to a
        /// page). Following stops once the drag moves the text: a pull of the sheet alone (a pull
        /// down from the top) keeps following, as it moves nothing.
        func observeDragging(_ scrollView: UIScrollView) {
            pullHandoff.onDragBegan = { [weak self] in
                self?.userTookOver()
                self?.chrome?.dragBegan()
            }
            pullHandoff.onMove = { [weak self] delta in
                guard let self, !jumpMode else { return }
                chrome?.dragged(by: delta)
            }
            pullHandoff.onScroll = { [weak self] in self?.stopFollowing() }
            pullHandoff.onRelease = { [weak self] velocity in self?.layout.dragEnded(velocity: velocity) }
            pullHandoff.attach(to: scrollView)
        }

        /// The user moved the text (a drag, a page turn, a link): the hold goes.
        func userTookOver() {
            hold = nil
            layout.cancelSettling()
        }

        /// The user moved the text while it followed the audio: it stops (Jump to Audio resumes).
        func stopFollowing() {
            guard follows else { return }
            follows = false
            onUserScroll()
        }

        /// Scrub-follow: the paragraph under the scrub thumb, in the middle.
        func scroll(_ request: ReaderScrollRequest?) {
            guard let request, request.token != lastScrollToken, webView != nil else { return }
            lastScrollToken = request.token
            layout.cancelSettling()
            hold = .paragraph(request.index)
            if loaded { showParagraph(request.index) }
        }

        /// Following turned on (Jump to Audio, or another page started): go to the spoken sentence.
        func setFollows(_ on: Bool) {
            guard on != follows else { return }
            follows = on
            if on { goToSpoken(.animate, explicit: true) }
        }

        // MARK: Going to the spoken sentence

        /// How the text goes to the spoken sentence.
        enum SpokenMove {
            /// At once, held there while the layout settles (opening, a reflow, Reduce Motion).
            case jump
            /// On the `Motion.standard` spring (Jump to Audio, a new paragraph).
            case animate
            /// On the spring, only when the sentence isn't wholly in the visible text: a long
            /// paragraph's sentences reaching its edge.
            case intoView
        }

        /// Where the text last went for the audio: the paragraph, and whether its sentence was
        /// known then (a sentence that comes later is gone to when it does).
        private var spokenShown: (paragraph: Int, hadSentence: Bool)?
        /// Counts requests to go to the sentence: only the newest one's answer moves the text.
        private var spokenRequest = 0

        /// The text goes to the spoken sentence: while following, or opened at the sentence and
        /// not moved since.
        var goesToSpoken: Bool { follows || hold == .spoken }

        /// Where that is: the sentence when it is in the spoken paragraph (or the sentence alone,
        /// with no paragraph spoken), else the spoken paragraph.
        var spokenSpot: (paragraph: Int, sentence: ReaderSentence?)? {
            guard let paragraph = pendingActive ?? pendingSentence?.paragraph else { return nil }
            return (paragraph, pendingSentence?.paragraph == paragraph ? pendingSentence : nil)
        }

        /// Shows the spoken sentence (else the spoken paragraph): in the middle of the visible
        /// text, or its page. A long paragraph's middle can be screens away from the sentence
        /// being read, so the sentence, not the paragraph, is what is shown. Going there drops a
        /// hand-over still being placed (following takes over at the next paragraph).
        /// Pages never follow the audio (C108): only an explicit move (opening at the sentence, a
        /// new layout keeping it, *Jump to Audio*) shows the spoken sentence's page.
        func goToSpoken(_ move: SpokenMove, explicit: Bool = false) {
            guard loaded, goesToSpoken, let spot = spokenSpot else { return }
            if let pages = layout as? PagesTextLayout {
                guard explicit else { return }
                handOverPlaced()
                return pages.show(spot: ReadingPages.Spot(spot))
            }
            if move != .intoView {
                layout.cancelSettling()
                handOverPlaced()
            }
            spokenShown = (spot.paragraph, spot.sentence != nil)
            spokenRequest += 1
            let request = spokenRequest
            let args = spot.sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "\(spot.paragraph), null, null"
            locate("window.__readerSpokenRect(\(args))") { [weak self] top, height in
                // While the sheet is pulled the text is held at its top; the next sentence goes.
                guard let self, request == spokenRequest, goesToSpoken, !pullHandoff.isPulling else { return }
                layout.show(top: top, height: height, .centre(move))
            }
        }

        func setActiveParagraph(_ index: Int?) {
            let changed = pendingActive != index
            pendingActive = index
            guard sentActive != .some(index), let webView, loaded else { return }
            sentActive = .some(index)
            let arg = index.map(String.init) ?? "null"
            webView.evaluateJavaScript(
                "window.__readerSetActive && window.__readerSetActive(\(arg));",
                completionHandler: nil
            )
            if changed, follows, let index {
                if layout is PagesTextLayout { return layout.follow(word: ReadingPages.Spot(paragraph: index, offset: 0)) }
                goToSpoken(.animate)
            }
        }

        func setSentence(_ sentence: ReaderSentence?) {
            pendingSentence = sentence
            guard sentSentence != .some(sentence), let webView, loaded else { return }
            sentSentence = .some(sentence)
            let args = sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "null"
            webView.evaluateJavaScript("window.__readerSetSentence && window.__readerSetSentence(\(args));",
                                       completionHandler: nil)
            guard let sentence else { return }
            // Opened at the sentence, which came after the page: it goes there now.
            if !follows, hold == .spoken { return goToSpoken(.jump, explicit: true) }
            if layout is PagesTextLayout { return }
            // Following, within the paragraph the text last went to: to its sentence when the text
            // went there before the sentence was known, else only to keep the sentence in view.
            guard follows, sentence.paragraph == pendingActive, let shown = spokenShown,
                  shown.paragraph == sentence.paragraph else { return }
            goToSpoken(shown.hadSentence ? .intoView : .animate)
        }

        /// The word being spoken (`HTMLReadingView.spokenWord`).
        private(set) var spokenWord: ReadingPages.Spot?

        /// Following, the layout keeps the spoken word on screen as it moves (Pages turns to the
        /// next page when it gets there; Scroll moves by the sentence).
        func setSpokenWord(_ word: ReadingPages.Spot?) {
            guard word != spokenWord else { return }
            spokenWord = word
            if loaded, follows, !pullHandoff.isPulling, let word { layout.follow(word: word) }
        }

        func setJumpMode(_ on: Bool) {
            jumpMode = on
            guard lastSentJumpMode != on, let webView, loaded else { return }
            lastSentJumpMode = on
            webView.evaluateJavaScript(
                "window.__readerSetJumpMode && window.__readerSetJumpMode(\(on));",
                completionHandler: nil
            )
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "readerBridge", let body = message.body as? [String: Any] else { return }
            if let x = body["tapX"] as? Double, let width = body["width"] as? Double {
                textTapped(x: CGFloat(x), width: CGFloat(width))
            } else if body["layout"] != nil {
                if loaded { layout.contentChanged() }
            } else if jumpMode, let index = body["index"] as? Int {
                DispatchQueue.main.async { self.onTapParagraph(index) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            // Sizes or the top view that changed while the page loaded: a fresh page, nothing to
            // keep in place yet. First, so the page is measured as it will be.
            sentSizes = sizes
            sentLook = look
            pageTopHeight = sentTopHeight.flatMap { topHost == nil ? nil : $0 }
            webView.evaluateJavaScript(ReadingStyle.variablesScript(sizes, look)
                + (pageTopHeight.map(Self.topHeightScript) ?? ""), completionHandler: nil)
            reapplyInsets()
            sentActive = nil
            setActiveParagraph(pendingActive)
            sentSentence = nil
            setSentence(pendingSentence)
            lastSentJumpMode = nil
            setJumpMode(jumpMode)
            layout.opened()
            guard case .handOver(let handOver) = hold else {
                measureTextTop()
                return placeHold()
            }
            // Handed over from the Reader: its top, or the same line at the same place on screen
            // (see `handOver`). A drag or scrub meanwhile drops it.
            measureTextTop { [weak self] in
                guard let self, hold == .handOver(handOver) else { return }
                layout.open(handOver: handOver)
            }
        }
    }
}

/// Where the line being read moved in a reflow (document y), and the text's top before and after.
struct ReadingReflow {
    var lineBefore: CGFloat
    var lineAfter: CGFloat
    var textTopBefore: CGFloat
    var textTopAfter: CGFloat

    /// How far the line moved on the page.
    var moved: CGFloat { lineAfter - lineBefore }
    /// How far it moved within the text (a change above the text alone moves `textTop`, not this).
    var movedInText: CGFloat { (lineAfter - textTopAfter) - (lineBefore - textTopBefore) }
}

/// How a layout shows a place in the text: in the middle of the visible text (the spoken sentence
/// or a scrubbed paragraph, gone to as the move says) or at its top (a link's target). Pages mode
/// shows the page holding it either way.
enum ReadingPlacement: Equatable {
    case centre(HTMLReadingWebView.Coordinator.SpokenMove)
    case top
}

/// How the reading text sits on screen: one column that scrolls (`ScrollTextLayout`) or a page
/// of whole lines at a time (`PagesTextLayout`). The coordinator decides what the text shows (its
/// hold, the spoken sentence, a scrub, a link) and finds where that is in the page; the layout
/// puts it on screen and keeps the reader's place through every new layout.
@MainActor
protocol ReadingTextLayout: AnyObject {
    /// A new page is loading.
    func reset()
    /// The page loaded, its insets set: a fresh page shows its top (the coordinator then places
    /// its hold).
    func opened()
    /// Puts another page's place (D2) on screen, then tells the coordinator (`handOverPlaced`).
    func open(handOver: ReadingHandOver)
    /// Shows the part of the page at document y `top`, `height` tall. False: it can't yet (Pages
    /// before its first measure), and the hold stays for when it can.
    @discardableResult func show(top: CGFloat, height: CGFloat, _ placement: ReadingPlacement) -> Bool
    /// A tap at an edge: a screen or a page on. False: there was nothing to turn to.
    func turn(forward: Bool) -> Bool
    func setInsets(_ insets: ReaderTextInsets)
    /// The document y of the line a reflow keeps, and whether the text is at its top.
    func reflowAnchor() -> (y: CGFloat, atTop: Bool)
    /// The page reflowed; the layout keeps the line, then the coordinator's hold goes back
    /// (`placeHold`).
    func reflowed(_ reflow: ReadingReflow, atTop: Bool)
    /// The page's layout changed by itself (loaded, an image arrived).
    func contentChanged()
    /// The web view laid out (on every pass: cheap when nothing changed).
    func viewportLaidOut()
    /// A drag on the text let go without pulling the sheet (`velocity` down positive).
    func dragEnded(velocity: CGFloat)
    /// Following the audio, the spoken word moved on.
    func follow(word: ReadingPages.Spot)
    /// An offset still being put on screen (a hand-over, the spoken sentence while the page lays
    /// out).
    var isSettling: Bool { get }
    func cancelSettling()
    /// The other layout takes over.
    func deactivate()
}

extension ReadingTextLayout {
    func contentChanged() {}
    func viewportLaidOut() {}
    func dragEnded(velocity: CGFloat) {}
    func follow(word: ReadingPages.Spot) {}
    var isSettling: Bool { false }
    func cancelSettling() {}
}

/// The reading page's web view: tells the coordinator when it is laid out (its width sizes the
/// title card).
final class ReadingWebView: WKWebView {
    var onLayout: (() -> Void)?
    var canPlayFromHere: () -> Bool = { false }
    var onPlayFromHere: () -> Void = {}

    /// The system edit menu on a selection gets *Play from Here* first (C109), beside Copy.
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard canPlayFromHere() else { return }
        let play = UIAction(title: String(localized: "Play from Here"), image: UIImage(systemName: "play")) {
            [weak self] _ in self?.onPlayFromHere()
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [play]), atStartOfMenu: .standardEdit)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
