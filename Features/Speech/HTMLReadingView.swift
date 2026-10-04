import Foundation
import SwiftUI
import WebKit

/// The spoken sentence inside the spoken paragraph: UTF-16 offsets into the paragraph's plain
/// text (the listen block's text, whitespace collapsed).
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

/// Lets the owner read the text's scroll offset (the Reader hands it to Now Playing, D2).
@MainActor
final class ReadingScrollHandle {
    fileprivate weak var webView: WKWebView?

    /// The scroll view's vertical content offset, nil before the page is up.
    var offset: CGFloat? { webView?.scrollView.contentOffset.y }
}

/// Renders an article's reading HTML on paper in the serif reading style, with the paragraph
/// tint, tap-to-start and, in Now Playing, following the audio:
/// - `follows`: on each new `activeParagraphIndex` the text scrolls it near the middle, animated
///   on the `Motion.standard` spring (a jump under Reduce Motion). A finger drag turns it off
///   (`onUserScroll`); the owner turns it back on (Back to audio), which scrolls to the paragraph.
/// - `sentence`: the spoken sentence is underlined (CSS Custom Highlight, iOS 17.2+; earlier
///   systems show the paragraph tint alone).
/// Without `follows` (the Reader) the text never scrolls by itself, except to follow a scrub.
/// Indices follow `ListenHTMLBlocks` leaf elements (same as speech).
struct HTMLReadingView: View {
    let html: String
    var heading: ReaderHeading? = nil
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
            heading: heading,
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
        .background(Palette.paper)
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
    var heading: ReaderHeading?
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
        c.opensAt = opensAt
        c.follows = follows
        c.sizes = sizes
        scrollHandle?.webView = webView
        c.load(html: html, heading: heading)
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

        let webView = WKWebView(frame: .zero, configuration: config)
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
        c.setTextInsets(textInsets)
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
        var animates = true
        /// Following the audio (Now Playing). Set before the first load by `makeUIView`.
        var follows = false
        /// The first load opens here (the Reader's offset, handed over to Now Playing).
        var opensAt: CGFloat?
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

        func load(html: String, heading: ReaderHeading? = nil) {
            lastHTML = html
            lastHeading = heading
            userScrolled = false
            loaded = false
            sentActive = nil
            sentSentence = nil
            sentSizes = sizes
            webView?.loadHTMLString(Self.wrap(html, heading: heading, sizes: sizes), baseURL: nil)
        }

        /// True once the user has dragged the text (until then it's pinned to the top).
        private var userScrolled = false

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
            if wasAtTop, !sv.isTracking, opensAt == nil, !follows {
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -insets.top)
            }
        }

        func setSizes(_ sizes: ReadingStyle.Sizes) {
            self.sizes = sizes
            guard loaded, sizes != sentSizes, let webView else { return }
            sentSizes = sizes
            webView.evaluateJavaScript(ReadingStyle.sizesScript(sizes), completionHandler: nil)
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
            if follows {
                follows = false
                onUserScroll()
            }
        }

        /// Scrub-follow: center the paragraph under the scrub thumb.
        func scroll(_ request: ReaderScrollRequest?) {
            guard let request, request.token != lastScrollToken, let webView else { return }
            lastScrollToken = request.token
            let js = "(function(){ var el = document.querySelector('[data-reader-index=\"\(request.index)\"]');"
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

        /// The one reading page (the Reader and Now Playing alike): paper, the serif body, the
        /// title and source line on top. The spoken paragraph's tint pads with a box-shadow, so it
        /// never reflows.
        private static func wrap(_ html: String, heading: ReaderHeading?, sizes: ReadingStyle.Sizes) -> String {
            let header = heading.map {
                "<header class=\"reader-heading\"><div class=\"reader-title\">\(escape($0.title))</div>"
                    + "<div class=\"reader-detail\">\(escape($0.detail))</div></header>"
            } ?? ""
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
            \(ReadingStyle.css(sizes: sizes, blockTags: ListenHTMLBlocks.tags))
            </style>
            </head>
            <body>
            \(header)
            \(html)
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
            let sv = webView.scrollView
            if let opensAt {
                // Handed over from the Reader: the text stays exactly where it was.
                self.opensAt = nil
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: opensAt)
            } else if follows, let index = pendingActive {
                center(paragraph: index, animated: false)
            } else {
                // A fresh page starts at the top, just below the top chrome.
                sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -textInsets.top)
            }
        }
    }

    /// Injected from `ListenHTMLBlocks.innerSelector` so JS and Swift share one tag list.
    private static var bootstrapJS: String {
        let sel = ListenHTMLBlocks.innerSelector
        return """
        (function() {
          var BLOCK_SEL = '\(sel)';
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
          // A DOM range over [start, end) of the element's text, counted the way the listen block
          // text is: whitespace runs (and no-break spaces) as one space, leading space dropped.
          function rangeIn(el, start, end) {
            var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
            var count = 0, lastSpace = true, range = document.createRange(), started = false, node;
            while ((node = walker.nextNode())) {
              var s = node.nodeValue;
              for (var i = 0; i < s.length; i++) {
                var space = /[\\s\\u00a0]/.test(s[i]);
                if (space && lastSpace) continue;
                if (!started && count >= start) { range.setStart(node, i); started = true; }
                if (started && count >= end) { range.setEnd(node, i); return range; }
                count += 1;
                lastSpace = space;
              }
            }
            if (!started) return null;
            range.setEndAfter(el.lastChild || el);
            return range;
          }
          window.__readerJump = false;
          window.__readerSetJumpMode = function(on) {
            window.__readerJump = !!on;
            document.body.classList.toggle('reader-jump', !!on);
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
        })();
        """
    }
}
