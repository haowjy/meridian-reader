import Foundation
import SwiftUI
import WebKit

/// The spoken sentence inside the spoken paragraph: UTF-16 offsets into the paragraph's text, as
/// the session counts them (`ListenHTMLBlocks` text, or a plain-text paragraph as it is).
struct ReaderSentence: Equatable {
    var paragraph: Int
    var start: Int
    var end: Int
}

/// The page's title and source line, drawn at the top of the text (part of the page, so it
/// scrolls with it; not a listen block, so it never shifts paragraph indices).
struct ReaderHeading: Equatable {
    var title: String
    /// "example.org · 9 min".
    var detail: String
}

/// A native view at the top of the text that scrolls with it, in place of the HTML title and
/// source line (Now Playing's title card). `id` says when it changed: the hosted view is only
/// replaced then.
struct ReadingTopView: Equatable {
    let id: AnyHashable
    let view: AnyView

    static func == (a: ReadingTopView, b: ReadingTopView) -> Bool { a.id == b.id }
}

/// Lets the owner read the text's scroll offset (the Reader hands it to Now Playing, D2).
@MainActor
final class ReadingScrollHandle {
    fileprivate weak var webView: WKWebView?
    fileprivate weak var coordinator: HTMLReadingWebView.Coordinator?

    /// The vertical scroll offset into the article text (from where it starts, below the title
    /// or the title card), so a page with something else above the text can open with the same
    /// line in the same place. Nil before the page is up.
    var offset: CGFloat? {
        guard let webView else { return nil }
        return webView.scrollView.contentOffset.y - (coordinator?.textTop ?? 0)
    }
}

/// Renders an article's reading HTML in the serif reading style (`look`: paper for the Reader,
/// the player's lyrics style for Now Playing), with tap-to-start and, in Now Playing, following
/// the audio:
/// - `follows`: on each new `activeParagraphIndex` the text scrolls it near the middle, animated
///   on the `Motion.standard` spring (a jump under Reduce Motion). A finger drag turns it off
///   (`onUserScroll`); the owner turns it back on (Back to audio), which scrolls to the paragraph.
/// - `sentence`: the spoken sentence is underlined (CSS Custom Highlight, iOS 17.2+; earlier
///   systems show the paragraph tint or full ink alone).
/// Without `follows` (the Reader) the text never scrolls by itself, except to follow a scrub.
/// Indices follow `ListenHTMLBlocks` leaf elements (same as speech).
struct HTMLReadingView: View {
    let html: String
    var look: ReadingStyle.Look = .paper
    /// The title and source line on top of the text (paper).
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
    /// Where the text opens (a scroll offset), instead of the top or the spoken paragraph.
    var opensAt: CGFloat? = nil
    var scrollHandle: ReadingScrollHandle? = nil
    /// Room left above / below the text for chrome drawn over it.
    var textInsets = ReaderTextInsets()
    var onUserScroll: () -> Void = {}
    let onTapParagraph: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HTMLReadingWebView(
            html: html,
            look: look,
            heading: heading,
            topView: topView,
            activeParagraphIndex: activeParagraphIndex,
            sentence: sentence,
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            follows: follows,
            opensAt: opensAt,
            scrollHandle: scrollHandle,
            textInsets: textInsets,
            sizes: ReadingStyle.Sizes(traits: UITraitCollection(preferredContentSizeCategory:
                UIContentSizeCategory(dynamicTypeSize))),
            animates: !reduceMotion,
            onUserScroll: onUserScroll,
            onTapParagraph: onTapParagraph
        )
        .background(look == .player ? Palette.playerBackground : Palette.paper)
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
    var look: ReadingStyle.Look = .paper
    var heading: ReaderHeading?
    var topView: ReadingTopView?
    let activeParagraphIndex: Int?
    var sentence: ReaderSentence?
    let jumpMode: Bool
    var scrollRequest: ReaderScrollRequest? = nil
    var follows = false
    var opensAt: CGFloat?
    var scrollHandle: ReadingScrollHandle?
    var textInsets = ReaderTextInsets()
    var sizes = ReadingStyle.Sizes()
    var animates = true
    var onUserScroll: () -> Void = {}
    let onTapParagraph: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapParagraph: onTapParagraph)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(coordinator: context.coordinator)
        let c = context.coordinator
        c.textInsets = textInsets
        c.follows = follows
        c.sizes = sizes
        c.look = look
        c.setTopView(topView)
        scrollHandle?.webView = webView
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
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
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
        c.animates = animates
        scrollHandle?.webView = webView
        scrollHandle?.coordinator = c
        c.setTextInsets(textInsets)
        c.setTopView(topView)
        if c.lastHTML != html || c.lastHeading != heading {
            c.load(html: html, heading: heading)
        }
        c.setSizes(sizes)
        c.setActiveParagraph(activeParagraphIndex)
        c.setSentence(sentence)
        c.setJumpMode(jumpMode)
        c.setFollows(follows)
        c.scroll(scrollRequest)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTapParagraph: (Int) -> Void
        var onUserScroll: () -> Void = {}
        weak var webView: WKWebView?
        var lastHTML: String = ""
        var lastHeading: ReaderHeading?
        var sizes = ReadingStyle.Sizes()
        private var sentSizes: ReadingStyle.Sizes?
        /// Set before the first load by `makeUIView`.
        var look: ReadingStyle.Look = .paper
        var animates = true
        /// Following the audio (Now Playing). Set before the first load by `makeUIView`.
        var follows = false
        /// The load in flight opens here (the Reader's offset, handed over to Now Playing).
        private var opensAt: CGFloat?
        private var loaded = false
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
        private var sentInsets: ReaderTextInsets?

        init(onTapParagraph: @escaping (Int) -> Void) {
            self.onTapParagraph = onTapParagraph
        }

        /// Shows `html`. `opensAt` is where this load opens (the D2 handoff); any other load opens
        /// at the top, or at the spoken paragraph when following, and drops a restore still waiting.
        func load(html: String, heading: ReaderHeading? = nil, opensAt: CGFloat? = nil) {
            lastHTML = html
            lastHeading = heading
            userScrolled = false
            loaded = false
            sentActive = nil
            sentSentence = nil
            sentSizes = sizes
            loadGeneration += 1
            cancelRestore()
            pendingScrollIndex = nil
            self.opensAt = opensAt
            textTop = 0
            let top = topHost == nil ? nil : sentTopHeight ?? 0
            webView?.loadHTMLString(Self.wrap(html, heading: heading, top: top, sizes: sizes, look: look), baseURL: nil)
        }

        // MARK: The top view (the title card)

        private var topHost: UIHostingController<AnyView>?
        private var topID: AnyHashable?
        /// The top view's height the page's slot holds; nil = not measured yet.
        private var sentTopHeight: CGFloat?
        private var measuredTopWidth: CGFloat = 0

        /// How far the article text starts below the top of the page's content (the title and
        /// source line, or the title card's slot); 0 with nothing above it. Measured on load and
        /// whenever what's above changes size.
        private(set) var textTop: CGFloat = 0

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

        private func sendTopHeight() {
            guard loaded, let webView, let height = sentTopHeight else { return }
            webView.evaluateJavaScript(
                "(function(){ var t = document.querySelector('.reader-top'); if (t) t.style.height = '\(Int(height))px'; })();",
                completionHandler: nil)
            measureTextTop()
        }

        /// Measures `textTop` (after any style change queued before it), then runs `then`.
        private func measureTextTop(then: (() -> Void)? = nil) {
            guard let webView else { return }
            let generation = loadGeneration
            let js = "(function(){ var t = document.querySelector('.reader-text'); if (!t) return 0;"
                + " var b = document.body; return t.getBoundingClientRect().top - b.getBoundingClientRect().top"
                + " - parseFloat(getComputedStyle(b).paddingTop); })();"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, generation == self.loadGeneration else { return }
                self.textTop = CGFloat((result as? Double) ?? 0)
                then?()
            }
        }

        /// True once the user has dragged the text (until then it's pinned to the top).
        private var userScrolled = false

        // MARK: Opening at a handed-over offset (D2)

        /// Counts loads, so a restore (and its timers) only acts on the page it was made for.
        private var loadGeneration = 0
        private var restore: ReadingScrollRestore?
        private var restoreObservations: [NSKeyValueObservation] = []
        private var lastLayoutChange: CFTimeInterval = 0
        /// How long layout must stay still before an offset the page can't reach is clamped
        /// (`quiet`), and the longest a restore waits at all (`limit`), in seconds.
        var restoreTiming = (quiet: 0.3, limit: 2.0)
        /// A handed-over offset is still waiting: for the page to load, or for its layout.
        var isRestoringScroll: Bool { restore != nil || opensAt != nil }

        /// Opens the text at offset `y` once the page's layout can hold it (`ReadingScrollRestore`).
        /// Content size, viewport and inset changes each try again.
        private func open(at y: CGFloat, in sv: UIScrollView) {
            let generation = loadGeneration
            restore = ReadingScrollRestore(offset: y, generation: generation)
            let changed: (UIScrollView) -> Void = { [weak self] _ in
                DispatchQueue.main.async { self?.layoutChanged(generation) }
            }
            restoreObservations = [
                sv.observe(\.contentSize) { sv, _ in changed(sv) },
                sv.observe(\.contentInset) { sv, _ in changed(sv) },
                sv.observe(\.frame) { sv, _ in changed(sv) },
            ]
            layoutChanged(generation)
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreTiming.limit) { [weak self] in
                self?.advanceRestore(generation, quiet: true, expired: true)
            }
        }

        private func layoutChanged(_ generation: Int) {
            guard restore?.generation == generation else { return }
            let now = CACurrentMediaTime()
            lastLayoutChange = now
            advanceRestore(generation, quiet: false, expired: false)
            let quiet = restoreTiming.quiet
            DispatchQueue.main.asyncAfter(deadline: .now() + quiet) { [weak self] in
                guard let self, self.lastLayoutChange == now else { return } // layout moved again
                self.advanceRestore(generation, quiet: true, expired: false)
            }
        }

        private func advanceRestore(_ generation: Int, quiet: Bool, expired: Bool) {
            guard let restore, restore.generation == generation, generation == loadGeneration,
                  let sv = webView?.scrollView else { return }
            let layout = ReadingScrollRestore.Layout(
                contentHeight: sv.contentSize.height, viewportHeight: sv.bounds.height,
                insetTop: sv.contentInset.top, insetBottom: sv.contentInset.bottom)
            guard case .scroll(let y) = restore.step(in: layout, quiet: quiet, expired: expired) else { return }
            sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: y)
            cancelRestore()
        }

        /// Drops a waiting restore, including one queued for a page still loading: a newer scroll
        /// (drag, scrub, follow) or another load wins.
        private func cancelRestore() {
            opensAt = nil
            restore = nil
            restoreObservations = []
        }

        /// A scrub that came before the page finished loading; it is applied when it does.
        private var pendingScrollIndex: Int?

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
            // Not a scroll of the text: it just keeps the first line below the top chrome.
            if wasAtTop, !sv.isTracking, opensAt == nil, restore == nil, !follows {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -insets.top)
            }
        }

        func setSizes(_ sizes: ReadingStyle.Sizes) {
            self.sizes = sizes
            guard loaded, sizes != sentSizes, let webView else { return }
            sentSizes = sizes
            webView.evaluateJavaScript(ReadingStyle.sizesScript(sizes), completionHandler: nil)
            measureTextTop()
        }

        /// Notes a finger drag: an inset change no longer pins the text to the top, and following
        /// stops. The pan recognizer, because WebKit owns the scroll view's delegate; programmatic
        /// scrolls never reach it.
        func observeDragging(_ scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(dragged(_:)))
        }

        @objc private func dragged(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .began else { return }
            userScrolled = true
            cancelRestore()
            if follows {
                follows = false
                onUserScroll()
            }
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
            let js = "(function(){ var el = document.querySelector('[data-reader-index=\"\(index)\"]');"
                + " if (el) el.scrollIntoView({block: 'center'}); })();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Following turned on (Back to audio, or another page started): go to the paragraph.
        func setFollows(_ on: Bool) {
            guard on != follows else { return }
            follows = on
            if on, let index = pendingActive { center(paragraph: index, animated: animates) }
        }

        /// Scrolls `paragraph` near the middle of the visible text with a native offset animation
        /// (JS `scrollIntoView` can't run on the motion tokens). The page reports the paragraph's
        /// rect in the web view's coordinates.
        private func center(paragraph index: Int, animated: Bool) {
            guard let webView, loaded else { return }
            cancelRestore()
            let js = "(function(){ var el = document.querySelector('[data-reader-index=\"\(index)\"]');"
                + " if (!el) return null; var r = el.getBoundingClientRect(); return [r.top, r.height]; })();"
            webView.evaluateJavaScript(js) { [weak self, weak webView] result, _ in
                guard let self, let webView, self.follows, let rect = result as? [Double], rect.count == 2 else { return }
                let sv = webView.scrollView
                let visible = sv.bounds.height - sv.contentInset.top - sv.contentInset.bottom
                let center = CGFloat(rect[0] + rect[1] / 2)
                let delta = center - (sv.contentInset.top + visible / 2)
                let maxY = max(-sv.contentInset.top, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
                let y = min(max(-sv.contentInset.top, sv.contentOffset.y + delta), maxY)
                guard abs(y - sv.contentOffset.y) > 1 else { return }
                let target = CGPoint(x: sv.contentOffset.x, y: y)
                if animated {
                    UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                                   options: [.allowUserInteraction, .beginFromCurrentState]) {
                        sv.contentOffset = target
                    }
                } else {
                    sv.contentOffset = target
                }
            }
        }

        /// The one reading page (the Reader and Now Playing alike): the serif body in `look`, with
        /// the title and source line on top, or a slot `top` points tall for the native top view.
        /// The article text is wrapped (`.reader-text`) so where it starts can be measured. The
        /// spoken paragraph's tint pads with a box-shadow, so it never reflows.
        private static func wrap(_ html: String, heading: ReaderHeading?, top: CGFloat?, sizes: ReadingStyle.Sizes,
                                 look: ReadingStyle.Look) -> String {
            let header: String
            if let top {
                header = "<div class=\"reader-top\" aria-hidden=\"true\" style=\"height: \(Int(top))px\"></div>"
            } else {
                header = heading.map {
                    "<header class=\"reader-heading\"><div class=\"reader-title\">\(escape($0.title))</div>"
                        + "<div class=\"reader-detail\">\(escape($0.detail))</div></header>"
                } ?? ""
            }
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
            \(ReadingStyle.css(sizes: sizes, blockTags: ListenHTMLBlocks.tags, look: look))
            </style>
            </head>
            <body>
            \(header)
            <main class="reader-text">
            \(html)
            </main>
            </body>
            </html>
            """
        }

        private static func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
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
            if changed, follows, let index { center(paragraph: index, animated: animates) }
        }

        func setSentence(_ sentence: ReaderSentence?) {
            pendingSentence = sentence
            guard sentSentence != .some(sentence), let webView, loaded else { return }
            sentSentence = .some(sentence)
            let args = sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "null"
            webView.evaluateJavaScript("window.__readerSetSentence && window.__readerSetSentence(\(args));",
                                       completionHandler: nil)
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
            guard message.name == "readerBridge" else { return }
            guard jumpMode else { return }
            if let body = message.body as? [String: Any], let index = body["index"] as? Int {
                DispatchQueue.main.async { self.onTapParagraph(index) }
            } else if let index = message.body as? Int {
                DispatchQueue.main.async { self.onTapParagraph(index) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            sentInsets = nil
            setTextInsets(textInsets)
            sentActive = nil
            setActiveParagraph(pendingActive)
            sentSentence = nil
            setSentence(pendingSentence)
            lastSentJumpMode = nil
            setJumpMode(jumpMode)
            sentSizes = nil
            setSizes(sizes)
            sendTopHeight()
            let sv = webView.scrollView
            if opensAt != nil {
                // Handed over from the Reader: the text stays exactly where it was, measured from
                // where the article text starts on each page. A drag or scrub meanwhile drops it.
                measureTextTop { [weak self, weak sv] in
                    guard let self, let sv, let opensAt = self.opensAt else { return }
                    self.opensAt = nil
                    self.open(at: opensAt + self.textTop, in: sv)
                }
            } else if let index = pendingScrollIndex {
                // Scrubbed while loading: the scrub is the newest request.
                pendingScrollIndex = nil
                scrollIntoView(paragraph: index)
            } else if follows, let index = pendingActive {
                center(paragraph: index, animated: false)
            } else if !userScrolled {
                // A fresh page starts at the top, just below the top chrome.
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -textInsets.top)
            }
        }
    }

    /// A paragraph's accessibility label in jump mode ("Paragraph 3") and its hint.
    static let jumpLabel = "Paragraph"
    static let jumpHint = "Plays from this paragraph"

    /// Injected from `ListenHTMLBlocks.innerSelector` so JS and Swift share one tag list.
    private static var bootstrapJS: String {
        let sel = ListenHTMLBlocks.innerSelector
        return """
        (function() {
          var BLOCK_SEL = '\(sel)';
          var JUMP_LABEL = '\(jumpLabel)', JUMP_HINT = '\(jumpHint)';
          function textOf(el) {
            return (el.textContent || '').split(String.fromCharCode(160)).join(' ').trim();
          }
          // Leaf listen blocks — same tag list + leaf rule as ListenHTMLBlocks in Swift.
          function blocks() {
            return Array.from(document.body.querySelectorAll(BLOCK_SEL)).filter(function(el) {
              if (el.closest('.reader-heading')) return false;
              if (textOf(el).length === 0) return false;
              return !el.querySelector(BLOCK_SEL);
            });
          }
          function reindex() {
            document.body.querySelectorAll(BLOCK_SEL).forEach(function(el) {
              el.removeAttribute('data-reader-index');
              el.onclick = null;
              el.classList.remove('reader-active');
            });
            blocks().forEach(function(el, i) {
              el.setAttribute('data-reader-index', String(i));
              el.onclick = function(ev) {
                if (!window.__readerJump) return;
                ev.preventDefault();
                window.webkit.messageHandlers.readerBridge.postMessage({ index: i });
              };
            });
          }
          // A DOM range over [start, end) of the block's text in the session's coordinates: UTF-16
          // units of the text ListenHTMLBlocks reads from it (every character of its text nodes, a
          // <br> as one space, script / style skipped, leading whitespace dropped). A plain-text
          // paragraph is that text exactly, so its spaces, tabs and newlines all count too.
          function rangeIn(el, start, end) {
            var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
            var count = 0, leading = true, range = document.createRange(), started = false, node;
            while ((node = walker.nextNode())) {
              if (node.nodeType === Node.ELEMENT_NODE) {
                if (node.tagName !== 'BR' || leading) continue;
                if (!started && count >= start) { range.setStartBefore(node); started = true; }
                if (started && count >= end) { range.setEndBefore(node); return range; }
                count += 1;
                continue;
              }
              var parent = node.parentNode && node.parentNode.nodeName;
              if (parent === 'SCRIPT' || parent === 'STYLE') continue;
              var s = node.nodeValue;
              for (var i = 0; i < s.length; i++) {
                if (leading) {
                  if (/\\s/.test(s[i])) continue;
                  leading = false;
                }
                if (!started && count >= start) { range.setStart(node, i); started = true; }
                if (started && count >= end) { range.setEnd(node, i); return range; }
                count += 1;
              }
            }
            if (!started) return null;
            range.setEndAfter(el.lastChild || el);
            return range;
          }
          window.__readerJump = false;
          // While ☝︎ is on each paragraph is a button to assistive tech, "Paragraph N" with the hint
          // "Plays from this paragraph"; off, it reads as text again.
          window.__readerSetJumpMode = function(on) {
            window.__readerJump = !!on;
            document.body.classList.toggle('reader-jump', !!on);
            document.querySelectorAll('[data-reader-index]').forEach(function(el) {
              if (on) {
                el.setAttribute('role', 'button');
                el.setAttribute('aria-label', JUMP_LABEL + ' ' + (Number(el.getAttribute('data-reader-index')) + 1));
                el.setAttribute('aria-description', JUMP_HINT);
              } else {
                el.removeAttribute('role');
                el.removeAttribute('aria-label');
                el.removeAttribute('aria-description');
              }
            });
          };
          window.__readerSetActive = function(index) {
            var el = (index === null || index === undefined) ? null
              : document.querySelector('[data-reader-index="' + index + '"]');
            // Already highlighted: touching the class would still invalidate its style.
            if (el && el.classList.contains('reader-active')) return;
            document.querySelectorAll('.reader-active').forEach(function(other) {
              other.classList.remove('reader-active');
            });
            // Highlight only: scrolling is Swift's (following, scrub).
            if (el) el.classList.add('reader-active');
            // The player's lyrics style dims the rest only while a paragraph is spoken.
            document.body.classList.toggle('reader-has-active', !!el);
          };
          window.__readerSetSentence = function(index, start, end) {
            if (!window.CSS || !CSS.highlights || typeof Highlight === 'undefined') return;
            CSS.highlights.delete('reader-sentence');
            if (index === null || index === undefined) return;
            var el = document.querySelector('[data-reader-index="' + index + '"]');
            var range = el && rangeIn(el, start, end);
            if (range) CSS.highlights.set('reader-sentence', new Highlight(range));
          };
          reindex();
          // The article's own leading heading already says the title: keep only the source line.
          (function() {
            var title = document.querySelector('.reader-title');
            var first = blocks()[0];
            var norm = function(t) { return (t || '').replace(/\\s+/g, ' ').trim().toLowerCase(); };
            if (title && first && /^H[1-3]$/.test(first.tagName) && norm(first.textContent) === norm(title.textContent)) {
              title.style.display = 'none';
            }
          })();
        })();
        """
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
