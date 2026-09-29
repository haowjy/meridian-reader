import Foundation
import SwiftUI
import WebKit

/// Renders cleaned article HTML with block highlight + tap-to-start.
/// Indices follow `ListenHTMLBlocks` leaf elements (same as speech).
struct HTMLReadingView: View {
    let html: String
    /// When non-nil, strip a matching leading title heading before load.
    /// Prefer passing already-stripped HTML (pageTitle nil) to avoid re-work on refresh.
    var pageTitle: String? = nil
    let activeParagraphIndex: Int?
    /// Taps only jump playback while this is on (scrolling / casual taps never skip).
    var jumpMode: Bool = false
    /// Scroll a paragraph into view. Only sent while the user scrubs (never by playback).
    var scrollRequest: ReaderScrollRequest? = nil
    /// Room left above / below the text for the reader's top row and bottom bars.
    var textInsets = ReaderTextInsets()
    let onTapParagraph: (Int) -> Void

    var body: some View {
        HTMLReadingWebView(
            html: displayHTML,
            activeParagraphIndex: activeParagraphIndex,
            jumpMode: jumpMode,
            scrollRequest: scrollRequest,
            textInsets: textInsets,
            onTapParagraph: onTapParagraph
        )
        .background(Color(.systemBackground))
    }

    private var displayHTML: String {
        guard let pageTitle else { return html }
        return ParagraphDocument.readingHTML(html, matchingTitle: pageTitle)
    }
}

private struct HTMLReadingWebView: UIViewRepresentable {
    let html: String
    let activeParagraphIndex: Int?
    let jumpMode: Bool
    var scrollRequest: ReaderScrollRequest? = nil
    var textInsets = ReaderTextInsets()
    let onTapParagraph: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapParagraph: onTapParagraph)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = config.userContentController
        userContent.add(context.coordinator, name: "readerBridge")
        userContent.addUserScript(WKUserScript(
            source: Self.bootstrapJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        // The view runs under the reader's bars; the scroll view's content inset (see
        // `setTextInsets`) keeps the first / last lines clear of them. Native
        // insets, not CSS padding: article HTML (e.g. Wikipedia's styles) can't override them.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.textInsets = textInsets
        context.coordinator.observeDragging(webView.scrollView)
        context.coordinator.load(html: html)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTapParagraph = onTapParagraph
        context.coordinator.setTextInsets(textInsets)
        if context.coordinator.lastHTML != html {
            context.coordinator.load(html: html)
        }
        context.coordinator.setActiveParagraph(activeParagraphIndex)
        context.coordinator.setJumpMode(jumpMode)
        context.coordinator.scroll(scrollRequest)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTapParagraph: (Int) -> Void
        weak var webView: WKWebView?
        var lastHTML: String = ""
        private var pendingActive: Int?
        private(set) var jumpMode = false
        private var lastSentJumpMode: Bool?
        private var lastScrollToken: Int?
        var textInsets = ReaderTextInsets()
        private var sentInsets: ReaderTextInsets?

        init(onTapParagraph: @escaping (Int) -> Void) {
            self.onTapParagraph = onTapParagraph
        }

        func load(html: String) {
            lastHTML = html
            userScrolled = false
            webView?.loadHTMLString(Self.wrap(html), baseURL: nil)
        }

        /// True once the user has dragged the text (until then it's pinned to the top).
        private var userScrolled = false

        /// Keeps the scroll view's top / bottom inset equal to the reader's bars, so the first line
        /// starts below the top row and the last one scrolls clear of the bottom controls.
        func setTextInsets(_ insets: ReaderTextInsets) {
            textInsets = insets
            guard insets != sentInsets, let webView else { return }
            sentInsets = insets
            let sv = webView.scrollView
            let wasAtTop = !userScrolled || sv.contentOffset.y <= -sv.contentInset.top + 2
            let inset = UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
            sv.contentInset = inset
            sv.verticalScrollIndicatorInsets = inset
            // Not a scroll of the text: it just keeps the first line below the top row.
            if wasAtTop, !sv.isTracking { sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -insets.top) }
        }

        /// Notes the first finger drag (then an inset change no longer pins the text to the top).
        /// The pan recognizer, because WebKit owns the scroll view's delegate.
        func observeDragging(_ scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(dragged(_:)))
        }

        @objc private func dragged(_ pan: UIPanGestureRecognizer) {
            if pan.state == .began { userScrolled = true }
        }

        /// Scrub-follow only: center the paragraph (never called by playback).
        func scroll(_ request: ReaderScrollRequest?) {
            guard let request, request.token != lastScrollToken, let webView else { return }
            lastScrollToken = request.token
            let js = "(function(){ var el = document.querySelector('[data-reader-index=\"\(request.index)\"]');"
                + " if (el) el.scrollIntoView({block: 'center'}); })();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        /// The one reading style (Browse and Saved alike): plain text; the current paragraph gets a
        /// soft tint whose padding is a box-shadow (no reflow when it moves). No cards, no bake marks
        /// (audio readiness shows as the scrubber's buffered fill instead).
        private static func wrap(_ html: String) -> String {
            let blockCSS = ListenHTMLBlocks.tags.map { "\($0) { margin: 0 0 14px; border-radius: 6px; }" }
                .joined(separator: "\n")
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
              :root { color-scheme: light dark; --hl: rgba(0,122,255,0.08); }
              @media (prefers-color-scheme: dark) { :root { --hl: rgba(10,132,255,0.16); } }
              html { -webkit-tap-highlight-color: transparent; }
              body { margin: 0; padding: 16px 22px 28px; font: -apple-system-body; line-height: 1.55;
                     -webkit-text-size-adjust: 100%; background: transparent; color: inherit; }
              h1, h2, h3, h4, h5, h6 { font-family: -apple-system, system-ui, sans-serif; line-height: 1.25; }
              h1 { font: -apple-system-title1; margin-bottom: 12px; }
              h2 { font: -apple-system-title2; }
              h3 { font: -apple-system-title3; }
              blockquote { margin: 0 0 14px; padding-left: 14px; opacity: 0.92; }
              ul, ol { padding-left: 1.2em; margin: 0 0 14px; }
              \(blockCSS)
              .reader-active { background: var(--hl); box-shadow: 0 0 0 6px var(--hl); }
              body.reader-jump [data-reader-index] {
                cursor: pointer;
                outline: 1px dashed color-mix(in srgb, #007AFF 45%, transparent);
                outline-offset: 3px;
              }
              body.reader-jump [data-reader-index]:active { background: color-mix(in srgb, #007AFF 18%, transparent); }
            </style>
            </head>
            <body>
            \(html)
            </body>
            </html>
            """
        }

        func setActiveParagraph(_ index: Int?) {
            pendingActive = index
            guard let webView else { return }
            let arg = index.map(String.init) ?? "null"
            webView.evaluateJavaScript(
                "window.__readerSetActive && window.__readerSetActive(\(arg));",
                completionHandler: nil
            )
        }

        func setJumpMode(_ on: Bool) {
            jumpMode = on
            guard lastSentJumpMode != on, let webView else { return }
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
            // A fresh page starts at the top, just below the top row.
            sentInsets = nil
            setTextInsets(textInsets)
            setActiveParagraph(pendingActive)
            lastSentJumpMode = nil
            setJumpMode(jumpMode)
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
          window.__readerJump = false;
          window.__readerSetJumpMode = function(on) {
            window.__readerJump = !!on;
            document.body.classList.toggle('reader-jump', !!on);
          };
          window.__readerSetActive = function(index) {
            document.querySelectorAll('.reader-active').forEach(function(el) {
              el.classList.remove('reader-active');
            });
            if (index === null || index === undefined) return;
            var el = document.querySelector('[data-reader-index="' + index + '"]');
            // Highlight only — do not scrollIntoView. User owns the viewport
            // during listen and while picking a jump target.
            if (el) {
              el.classList.add('reader-active');
            }
          };
          reindex();
        })();
        """
    }
}
