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
/// (`HTMLReadingView+Pages.swift`), with the page and `pageTimeLeft` in a footer.
/// Links open through `onOpenLink`.
/// Indices follow `ListenHTMLBlocks` leaf elements (same as speech).
struct HTMLReadingView: View {
    let html: String
    /// The title and source line on top of the text (the Reader).
    var heading: ReaderHeading? = nil
    /// A native view on top of the text instead (the player's title card).
    var topView: ReadingTopView? = nil
    let activeParagraphIndex: Int?
    var sentence: ReaderSentence? = nil
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
    /// the UTF-16 offset in it), "2 min left in chapter"; nil shows the page alone.
    var pageTimeLeft: (_ paragraph: Int, _ offset: Int) -> String? = { _, _ in nil }
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
        HTMLReadingWebView(
            html: html,
            look: ReadingStyle.Look(colors: ReadingStyle.Colors(palette, scheme: colorScheme), font: appearance.font,
                                    lineSpacing: appearance.lineSpacing, textScale: appearance.textScale),
            heading: heading,
            topView: topView,
            activeParagraphIndex: activeParagraphIndex,
            sentence: sentence,
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
            sizes: ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory:
                UIContentSizeCategory(dynamicTypeSize))),
            animates: !reduceMotion,
            onUserScroll: onUserScroll,
            onOpenLink: onOpenLink,
            onTapParagraph: onTapParagraph
        )
        .background(palette.background)
        .overlay {
            if paged { ReadingPageFrame(pages: pages, palette: palette, timeLeft: pageTimeLeft) }
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
    let onTapParagraph: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapParagraph: onTapParagraph)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(coordinator: context.coordinator)
        let c = context.coordinator
        c.textInsets = textInsets
        c.pages = pages
        c.pageFooter = pageFooter
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
        c.onUserScroll = onUserScroll
        c.onOpenLink = onOpenLink
        c.chrome = chrome
        // In full screen a pull at the top only rubber-bands (and brings the bars back); the
        // drag in progress keeps what it began with (`SheetPullTracking.canPull`).
        c.pullHandoff.handoff = fullScreen ? nil : context.environment.sheetPullHandoff
        c.animates = animates
        scrollHandle?.coordinator = c
        c.setPages(pages, footer: pageFooter)
        c.setTextInsets(textInsets)
        c.setTopView(topView)
        if c.lastHTML != html || c.lastHeading != heading {
            c.load(html: html, heading: heading)
        }
        c.setSizes(sizes)
        c.setLook(look)
        // The sentence first: a new paragraph goes straight to its sentence.
        c.setSentence(sentence)
        c.setActiveParagraph(activeParagraphIndex)
        c.setJumpMode(jumpMode)
        c.setFollows(follows)
        c.scroll(scrollRequest)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTapParagraph: (Int) -> Void
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
        /// The load in flight opens here (the Reader's `handOver`, handed to Now Playing).
        var opensAt: ReadingHandOver?
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
        var textInsets = ReaderTextInsets()
        var sentInsets: ReaderTextInsets?
        /// Pages mode's state (nil in Scroll mode) and the room under its pages; see
        /// `HTMLReadingView+Pages.swift`.
        var pages: ReadingPages?
        var pageFooter: CGFloat = 0
        /// The room the page has below its text for the last page to reach the top (0 in Scroll
        /// mode).
        var pageRoom: CGFloat = 0

        init(onTapParagraph: @escaping (Int) -> Void) {
            self.onTapParagraph = onTapParagraph
        }

        /// Shows `html`. `opensAt` is where this load opens (the D2 handoff); any other load opens
        /// at the top, or at the spoken sentence when following or `opensAtSentence`, and drops a
        /// restore still waiting.
        func load(html: String, heading: ReaderHeading? = nil, opensAt: ReadingHandOver? = nil) {
            lastHTML = html
            lastHeading = heading
            userScrolled = false
            loaded = false
            sentActive = nil
            sentSentence = nil
            sentSizes = sizes
            sentLook = look
            loadGeneration += 1
            cancelRestore()
            pendingScrollIndex = nil
            spokenShown = nil
            spokenOpenPending = opensAtSentence
            self.opensAt = opensAt
            textTop = 0
            reflowing = false
            queuedReflow = []
            pages?.reset()
            pageRoom = 0
            let top = topHost == nil ? nil : sentTopHeight ?? 0
            pageTopHeight = top
            webView?.loadHTMLString(Self.wrap(html, heading: heading, top: top, sizes: sizes, look: look), baseURL: nil)
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
        var textTop: CGFloat = 0

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

        /// Where a restore puts the text.
        private enum RestoreTarget: Equatable {
            /// Another page's position (D2).
            case handOver(ReadingHandOver)
            /// The spoken sentence in the middle: the scroll offset, `offset` points below the
            /// text's top (so it moves with the text, not with the web view on screen).
            case spoken(offset: CGFloat)
        }

        /// The scroll offset that opens this page at `target`.
        private func contentOffset(for target: RestoreTarget, in webView: WKWebView) -> CGFloat {
            switch target {
            case .handOver(.top): -webView.scrollView.contentInset.top
            case .handOver(.text(let offset)): offset + textTop + viewportTop(of: webView)
            case .spoken(let offset): offset + textTop
            }
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

        /// Sizes the top view to the page's width (inset by `Spacing.m`, at the body's top padding)
        /// and makes the page's slot under it as tall.
        func layoutTopView() {
            layoutPages()
            guard let webView, let host = topHost else { return }
            let width = webView.bounds.width - 2 * Spacing.m
            guard width > 0 else { return }
            if host.view.superview == nil { webView.scrollView.addSubview(host.view) }
            if width != measuredTopWidth {
                measuredTopWidth = width
                let height = ceil(host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                host.view.frame = CGRect(x: Spacing.m, y: Spacing.xs, width: width, height: height)
                if height != sentTopHeight {
                    sentTopHeight = height
                    sendTopHeight()
                }
            }
        }

        /// Gives the page's slot the top view's height, keeping the line being read in place.
        private func sendTopHeight() {
            guard loaded, let height = sentTopHeight, height != pageTopHeight else { return }
            // What is above the text moves the text by as much, and a hand-over still waiting
            // works out its offset from `textTop` on the next frame: say so before the page has
            // answered (it confirms it, see `reflow`).
            if let old = pageTopHeight, restore != nil { textTop += height - old }
            pageTopHeight = height
            reflow(Self.topHeightScript(height))
        }

        private static func topHeightScript(_ height: CGFloat) -> String {
            "var t = document.querySelector('.reader-top'); if (t) t.style.height = '\(Int(height))px';"
        }

        /// Measures `textTop` (after any style change queued before it), then runs `then`.
        func measureTextTop(then: (() -> Void)? = nil) {
            guard let webView else { return }
            let generation = loadGeneration
            webView.evaluateJavaScript("window.__readerTextTop()") { [weak self] result, _ in
                guard let self, generation == self.loadGeneration else { return }
                self.textTop = CGFloat((result as? Double) ?? 0)
                then?()
            }
        }

        /// True once the user has dragged the text (until then it's pinned to the top).
        private var userScrolled = false

        // MARK: Opening at a handed-over offset (D2) or the spoken sentence

        /// Counts loads, so a restore (and its timers) only acts on the page it was made for.
        private(set) var loadGeneration = 0
        /// A hand-over (or the spoken sentence) being put on screen: worked out again on every frame
        /// (`restoreFrame`) until layout has been still for `restoreTiming.quiet`.
        private var restore: (target: RestoreTarget, generation: Int, started: CFTimeInterval)?
        private var restoreLink: CADisplayLink?
        /// The last frame's target and layout, and when they last changed.
        private var restoreSeen: (target: CGFloat, layout: ReadingScrollRestore.Layout)?
        private var restoreSeenChanged: CFTimeInterval = 0
        /// How long the target and layout must stay still before the restore finishes (and an offset
        /// the page can't reach is clamped), and the longest a restore lasts at all, in seconds.
        var restoreTiming = (quiet: 0.3, limit: 2.0)

        /// Opens the text at `target` once the page's layout can hold it, and keeps it there while
        /// the layout settles: the title card measured, the header growing, what is above the text
        /// changing size (see `ReadingScrollRestore`).
        private func open(at target: RestoreTarget) {
            let now = CACurrentMediaTime()
            restore = (target, loadGeneration, now)
            restoreSeen = nil
            restoreSeenChanged = now
            restoreLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(restoreFrame))
            link.add(to: .main, forMode: .common)
            restoreLink = link
            restoreFrame()
        }

        @objc private func restoreFrame() {
            guard let restore, restore.generation == loadGeneration, let webView else { return cancelRestore() }
            let sv = webView.scrollView
            let target = contentOffset(for: restore.target, in: webView)
            let layout = ReadingScrollRestore.Layout(
                contentHeight: sv.contentSize.height, viewportHeight: sv.bounds.height,
                insetTop: sv.contentInset.top, insetBottom: sv.contentInset.bottom)
            let now = CACurrentMediaTime()
            if restoreSeen.map({ abs($0.target - target) > 0.01 || $0.layout != layout }) ?? true {
                restoreSeen = (target, layout)
                restoreSeenChanged = now
            }
            let quiet = now - restoreSeenChanged >= restoreTiming.quiet
            let expired = now - restore.started >= restoreTiming.limit
            let step = ReadingScrollRestore(offset: target, generation: restore.generation)
                .step(in: layout, quiet: quiet, expired: expired)
            guard case .scroll(let y) = step else { return }
            if abs(sv.contentOffset.y - y) > 0.01 { sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: y) }
            if quiet || expired { cancelRestore() }
        }

        /// Drops a waiting restore, including one queued for a page still loading: a newer scroll
        /// (drag, scrub, follow) or another load wins.
        func cancelRestore() {
            opensAt = nil
            restore = nil
            restoreLink?.invalidate()
            restoreLink = nil
        }

        // MARK: Reflow (Dynamic Type, the title card) keeps the line being read

        private var reflowing = false
        private var queuedReflow: [String] = []

        /// Runs `change` (a style change that reflows the page) keeping the line being read where
        /// it is on screen: the reading anchor, the paragraph and the UTF-16 offset of the first
        /// character on the line at the top of the reading area, measured before and after the
        /// change in one go. A page at its top stays at its top; one going to the spoken sentence
        /// centres it again; a hand-over still waiting keeps its line instead. Changes
        /// run one at a time, so each anchor is measured on the page as the last one left it.
        private func reflow(_ change: String) {
            guard loaded, let webView else { return }
            guard !reflowing else { return queuedReflow.append(change) }
            reflowing = true
            let sv = webView.scrollView
            let generation = loadGeneration
            let waiting: CGFloat? = if case .handOver(.text(let offset)) = restore?.target { offset } else { nil }
            let atTop = sv.contentOffset.y <= -sv.contentInset.top + 1
            // The document y of the top of the reading area (for a hand-over, where it will be).
            let anchorY = waiting.map { textTop + max(0, viewportTop(of: webView) + sv.contentInset.top + $0) }
                ?? sv.contentOffset.y + sv.contentInset.top
            let js = "(function(){ var a = window.__readerAnchor(\(Double(anchorY))); \(change)"
                + " return window.__readerAnchorMoved(a); })();"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, generation == self.loadGeneration else { return }
                self.reflowing = false
                if let moved = result as? [Double], moved.count == 4 {
                    self.reflowed(lineBefore: moved[0], lineAfter: moved[1], textTopBefore: moved[2],
                                  textTopAfter: moved[3], atTop: atTop)
                }
                if !self.queuedReflow.isEmpty {
                    let next = self.queuedReflow.joined(separator: " ")
                    self.queuedReflow = []
                    self.reflow(next)
                }
            }
        }

        private func reflowed(lineBefore: Double, lineAfter: Double, textTopBefore: Double, textTopAfter: Double,
                              atTop: Bool) {
            guard let sv = webView?.scrollView else { return }
            textTop = CGFloat(textTopAfter)
            // Pages keep the page holding the line being read (its first character, or the
            // spoken sentence while following).
            if pages != nil { return measurePages(follow: true) }
            if let restore {
                switch restore.target {
                case .handOver(.text(let offset)):
                    // Still opening: the target follows the line through the text (a change above
                    // the text alone moves `textTop`, which the next frame reads).
                    let moved = (lineAfter - textTopAfter) - (lineBefore - textTopBefore)
                    self.restore?.target = .handOver(.text(offset: offset + CGFloat(moved)))
                case .spoken:
                    goToSpoken(.jump)
                case .handOver(.top):
                    break
                }
            } else if atTop {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -sv.contentInset.top)
            } else if goesToSpoken, spokenSpot != nil {
                goToSpoken(.jump)
            } else {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: sv.contentOffset.y + CGFloat(lineAfter - lineBefore))
            }
        }

        /// A scrub that came before the page finished loading; it is applied when it does.
        var pendingScrollIndex: Int?

        /// Keeps the scroll view's top / bottom inset equal to the chrome over the text, so the
        /// first line starts below it and the last one scrolls clear of it.
        func setTextInsets(_ insets: ReaderTextInsets) {
            textInsets = insets
            guard insets != sentInsets, let webView else { return }
            sentInsets = insets
            let sv = webView.scrollView
            let wasAtTop = !userScrolled || sv.contentOffset.y <= -sv.contentInset.top + 2
            let inset = UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
            sv.contentInset = inset
            sv.verticalScrollIndicatorInsets = inset
            if pages != nil { return setPageRoom() }
            guard !sv.isTracking, opensAt == nil, !follows else { return }
            if opensAtSentence, !userScrolled, spokenSpot != nil {
                // Opened at the sentence: keep it in the middle of the new visible text.
                goToSpoken(.jump)
            } else if wasAtTop, restore == nil {
                // Not a scroll of the text: it just keeps the first line below the top chrome.
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -insets.top)
            }
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
        /// goes to the bars (none in jump mode); let go in Pages mode, it turns a page. Following
        /// stops once the drag moves the text: a pull of the sheet alone (a pull down from the
        /// top) keeps following, as it moves nothing.
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
            pullHandoff.onRelease = { [weak self] velocity in self?.pageDragEnded(velocity: velocity) }
            pullHandoff.attach(to: scrollView)
        }

        /// The user moved the text (a drag, a page turn): an inset change no longer pins it to the
        /// top, and a waiting restore is dropped.
        func userTookOver() {
            userScrolled = true
            spokenOpenPending = false
            cancelRestore()
        }

        /// The user moved the text while it followed the audio: it stops (Jump to Audio resumes).
        func stopFollowing() {
            guard follows else { return }
            follows = false
            onUserScroll()
        }

        /// Scrub-follow: center the paragraph under the scrub thumb.
        func scroll(_ request: ReaderScrollRequest?) {
            guard let request, request.token != lastScrollToken, webView != nil else { return }
            lastScrollToken = request.token
            cancelRestore()
            guard loaded else {
                pendingScrollIndex = request.index
                return
            }
            scrollIntoView(paragraph: request.index)
        }

        private func scrollIntoView(paragraph index: Int) {
            guard let webView else { return }
            if pages != nil { return showPage(holdingParagraph: index) }
            let js = "(function(){ var el = document.querySelector('[data-reader-index=\"\(index)\"]');"
                + " if (el) el.scrollIntoView({block: 'center'}); })();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Following turned on (Jump to Audio, or another page started): go to the spoken sentence.
        func setFollows(_ on: Bool) {
            guard on != follows else { return }
            follows = on
            if on { goToSpoken(.animate) }
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
        /// Counts requests to go to the sentence: only the newest one's answer scrolls.
        private var spokenRequest = 0
        /// `opensAtSentence` and the page hasn't been to the sentence yet (it may come after the
        /// page loads).
        private var spokenOpenPending = false

        /// The text goes to the spoken sentence: while following, or opened at the sentence and
        /// not dragged since.
        var goesToSpoken: Bool { follows || (opensAtSentence && !userScrolled) }

        /// Where that is: the sentence when it is in the spoken paragraph (or the sentence alone,
        /// with no paragraph spoken), else the spoken paragraph.
        var spokenSpot: (paragraph: Int, sentence: ReaderSentence?)? {
            guard let paragraph = pendingActive ?? pendingSentence?.paragraph else { return nil }
            return (paragraph, pendingSentence?.paragraph == paragraph ? pendingSentence : nil)
        }

        /// Puts the spoken sentence (else the spoken paragraph) in the middle of the visible text.
        /// The page says where it sits in the document; the scroll is native (JS scrolling can't
        /// run on the motion tokens). A long paragraph's middle can be screens away from the
        /// sentence being read, so the sentence, not the paragraph, is what goes to the middle.
        func goToSpoken(_ move: SpokenMove) {
            guard let webView, loaded, goesToSpoken, let spot = spokenSpot else { return }
            if move != .intoView { cancelRestore() }
            // Not paginated yet: the pages open on it.
            if let pages, pages.pagination == nil { return pages.start = ReadingPages.Spot(spot) }
            spokenShown = (spot.paragraph, spot.sentence != nil)
            spokenRequest += 1
            let request = spokenRequest, generation = loadGeneration
            let args = spot.sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "\(spot.paragraph), null, null"
            webView.evaluateJavaScript("window.__readerSpokenRect(\(args))") { [weak self, weak webView] result, _ in
                // While the sheet is pulled the text is held at its top; the next sentence goes.
                guard let self, let webView, generation == self.loadGeneration, request == self.spokenRequest,
                      self.goesToSpoken, !self.pullHandoff.isPulling,
                      let rect = result as? [Double], rect.count == 3 else { return }
                self.textTop = CGFloat(rect[2])
                if self.pages != nil { return self.showPage(holding: CGFloat(rect[0])) }
                self.scroll(toSpokenAt: CGFloat(rect[0]), height: CGFloat(rect[1]), move, in: webView.scrollView)
            }
        }

        /// Scrolls the spoken sentence, `height` tall at document y `top`, to the middle of the
        /// visible text: between the bars, or the whole screen while they are hidden (the bars
        /// coming back over it never move it).
        private func scroll(toSpokenAt top: CGFloat, height: CGFloat, _ move: SpokenMove, in sv: UIScrollView) {
            // Full screen: from the screen's top edge (the strip above the sheet shows the page's
            // colour) to its foot.
            let fullScreen = chrome?.hidden == true
            let insetTop = fullScreen ? -sv.convert(CGPoint(x: 0, y: sv.bounds.minY), to: nil).y : sv.contentInset.top
            let visibleTop = sv.contentOffset.y + insetTop
            let visible = sv.bounds.height - insetTop - (fullScreen ? 0 : sv.contentInset.bottom)
            if move == .intoView {
                // Opening still holds the page; a sentence in view stays where it is.
                guard restore == nil, top < visibleTop || top + height > visibleTop + visible else { return }
            }
            let y = top + height / 2 - insetTop - visible / 2
            let layout = ReadingScrollRestore.Layout(
                contentHeight: sv.contentSize.height, viewportHeight: sv.bounds.height,
                insetTop: sv.contentInset.top, insetBottom: sv.contentInset.bottom)
            // Before the scroll view holds the page's layout an offset doesn't stick: the restore
            // waits for it.
            guard move != .jump, animates, layout.isLaidOut else { return open(at: .spoken(offset: y - textTop)) }
            let target = min(max(y, layout.range.lowerBound), layout.range.upperBound)
            guard abs(target - sv.contentOffset.y) > 1 else { return }
            UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: target)
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
            if changed, follows, index != nil { goToSpoken(.animate) }
        }

        func setSentence(_ sentence: ReaderSentence?) {
            pendingSentence = sentence
            guard sentSentence != .some(sentence), let webView, loaded else { return }
            sentSentence = .some(sentence)
            let args = sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "null"
            webView.evaluateJavaScript("window.__readerSetSentence && window.__readerSetSentence(\(args));",
                                       completionHandler: nil)
            guard let sentence else { return }
            if spokenOpenPending {
                spokenOpenPending = false
                return goToSpoken(.jump)
            }
            // Following, within the paragraph the text last went to: to its sentence when the text
            // went there before the sentence was known, else only to keep the sentence in view.
            guard follows, sentence.paragraph == pendingActive, let shown = spokenShown,
                  shown.paragraph == sentence.paragraph else { return }
            goToSpoken(shown.hadSentence ? .intoView : .animate)
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
                if loaded { measurePages() }
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
            sentInsets = nil
            setTextInsets(textInsets)
            sentActive = nil
            setActiveParagraph(pendingActive)
            sentSentence = nil
            setSentence(pendingSentence)
            lastSentJumpMode = nil
            setJumpMode(jumpMode)
            let sv = webView.scrollView
            if pages != nil {
                openPages()
            } else if opensAt != nil {
                // Handed over from the Reader: its top, or the same line at the same place on
                // screen (see `handOver`). A drag or scrub meanwhile drops it.
                measureTextTop { [weak self] in
                    guard let self, let opensAt = self.opensAt else { return }
                    self.opensAt = nil
                    self.open(at: .handOver(opensAt))
                }
            } else if let index = pendingScrollIndex {
                // Scrubbed while loading: the scrub is the newest request.
                pendingScrollIndex = nil
                scrollIntoView(paragraph: index)
            } else if follows, pendingActive != nil {
                goToSpoken(.jump)
            } else if spokenOpenPending, pendingSentence != nil {
                spokenOpenPending = false
                goToSpoken(.jump)
            } else if !userScrolled {
                // A fresh page starts at the top, just below the top chrome.
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -textInsets.top)
            }
            if opensAt == nil { measureTextTop() }
        }
    }
}

/// The reading page's web view: tells the coordinator when it is laid out (its width sizes the
/// title card).
final class ReadingWebView: WKWebView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
