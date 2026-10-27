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
    /// The title shows elsewhere (C141: the player card), so neither it nor the article's own
    /// matching leading heading shows in the text.
    var titleHidden = false
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
///   sentence. With it off, `onSpotSide` says which way the spoken sentence is from the visible text
///   (above or below; Pages: an earlier or a later page): Jump to Audio's arrow.
/// - `sentence`: the spoken sentence is underlined (CSS Custom Highlight, iOS 17.2+; earlier
///   systems show the paragraph's highlight alone).
/// - `opensAtSentence` (the Reader, at a saved listening spot): the text opens with `sentence`
///   in the middle, and keeps it there through layout changes until the text is dragged.
/// Without `follows` (the Reader) the text never scrolls by itself after that, except to follow
/// a scrub.
/// In a reading page (`readingChrome` in the environment) the text runs under the page's bars,
/// its scroll insets their heights, and taps on it drive full screen (see
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
    /// The title and source line on top of the text.
    var heading: ReaderHeading? = nil
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
    /// Where the spoken sentence is from the visible text, while the text isn't following it.
    var onSpotSide: (JumpDirection) -> Void = { _ in }
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
            onSpotSide: onSpotSide,
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
    var onSpotSide: (JumpDirection) -> Void = { _ in }
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
        webView.onLayout = { [weak coordinator] in coordinator?.layout.viewportLaidOut() }
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
        c.onSpotSide = onSpotSide
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

/// The reading page's web view: tells the coordinator when it is laid out.
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
