import SwiftUI
import WebKit

/// The reading page's taps and links, and what it tells the sheet's bars (`ReadingChrome`):
/// - A finger drag on the text reports its movement (`dragged(by:)`), which hides or shows the
///   bars. Programmatic scrolls (following the audio, a scrub, a restore) never report.
/// - A tap on the text that isn't on a link (the page's script posts where it landed, see
///   `bootstrapJS`): the middle toggles the bars, the right edge goes forward a screen and the
///   left back one (`ReadingChrome.TapZone`), on the `Motion.standard` spring (a jump under Reduce
///   Motion); in Pages mode a whole page, at once (`turnPage`). A page turn is the user moving the text, like a drag: following the audio stops.
///   In ☝︎ jump mode taps play from a paragraph instead and nothing here runs; outside a reading
///   sheet (no chrome: Follow's preview) taps do nothing.
/// - A web link opens through the owner (`onOpenLink`: the browser); any other link (`mailto:`,
///   `data:`, a book's own links, made absolute under `ReadabilityRunner.placeholderBase`) does
///   nothing. A link to a place on the page goes there (in Pages mode, to the page holding it).
///   The reading view itself never leaves its page.
extension HTMLReadingWebView.Coordinator {
    /// The page's script reported a tap at `x` across a page `width` wide.
    func textTapped(x: CGFloat, width: CGFloat) {
        guard !jumpMode, let chrome, width > 0 else { return }
        switch ReadingChrome.TapZone(x: x, width: width) {
        case .none:
            break
        case .centre:
            chrome.tappedCentre()
        case .previous:
            pages == nil ? turnScreen(forward: false) : turnPage(forward: false)
            chrome.revealFloatingControl()
        case .next:
            pages == nil ? turnScreen(forward: true) : turnPage(forward: true)
            chrome.revealFloatingControl()
        }
    }

    /// One reading line, in points: the body text's size at this text size, times the spacing.
    private var lineHeight: CGFloat {
        sizes.body * CGFloat(look.textScale) * CGFloat(look.lineSpacing.multiple)
    }

    /// Scrolls the text by the visible reading area (the whole web view in full screen, between
    /// the bars otherwise) less one line, so the line at one edge stays in view at the other.
    /// Clamped to the content.
    private func turnScreen(forward: Bool) {
        guard let webView, loaded else { return }
        let sv = webView.scrollView
        let fullScreen = chrome?.hidden == true
        let visible = sv.bounds.height - (fullScreen ? 0 : sv.contentInset.top + sv.contentInset.bottom)
        let step = max(visible - lineHeight, lineHeight)
        let layout = ReadingScrollRestore.Layout(
            contentHeight: sv.contentSize.height, viewportHeight: sv.bounds.height,
            insetTop: sv.contentInset.top, insetBottom: sv.contentInset.bottom)
        guard layout.isLaidOut else { return }
        let target = min(max(sv.contentOffset.y + (forward ? step : -step), layout.range.lowerBound),
                         layout.range.upperBound)
        guard abs(target - sv.contentOffset.y) > 0.5 else { return }
        userTookOver()
        stopFollowing()
        scrollText(to: target)
    }

    // MARK: Links

    /// The page itself loads (the reading HTML, a reload) and embeds in it load. A link on it: a
    /// place on the page is gone to (`goToAnchor`), a web address opens through the owner,
    /// anything else does nothing. Nothing else takes the reading view anywhere.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.navigationType == .linkActivated || action.targetFrame == nil {
            decisionHandler(.cancel)
            if let fragment = Self.fragment(of: url, on: webView.url) { return goToAnchor(fragment) }
            if url.isWebOrTestPage, url.host() != ReadabilityRunner.placeholderBase.host() { onOpenLink(url) }
            return
        }
        // A frame inside the page (an embed) loads as it would; the page's own frame only loads
        // the reading HTML.
        let isPage = action.targetFrame?.isMainFrame != false
        decisionHandler(!isPage || url.absoluteString == "about:blank" ? .allow : .cancel)
    }

    /// A link to a place on the page (`fragment`, an element's id or name): it goes to the top of
    /// the reading area, on the `Motion.standard` spring (in Pages mode, the page holding it, at
    /// once). WebKit's own fragment navigation doesn't scroll a page loaded from a string. The
    /// user moved the text, as with a page turn: following stops.
    private func goToAnchor(_ fragment: String) {
        guard let webView, loaded, let data = try? JSONSerialization.data(withJSONObject: [fragment]),
              let arg = String(data: data, encoding: .utf8) else { return }
        let generation = loadGeneration
        webView.evaluateJavaScript("window.__readerAnchorTop(\(arg)[0])") { [weak self] result, _ in
            guard let self, let webView = self.webView, generation == loadGeneration,
                  let top = (result as? Double).map({ CGFloat($0) }) else { return }
            userTookOver()
            stopFollowing()
            if pages != nil { return showPage(holding: top) }
            let sv = webView.scrollView
            let layout = ReadingScrollRestore.Layout(
                contentHeight: sv.contentSize.height, viewportHeight: sv.bounds.height,
                insetTop: sv.contentInset.top, insetBottom: sv.contentInset.bottom)
            let y = min(max(top - sv.contentInset.top, layout.range.lowerBound), layout.range.upperBound)
            scrollText(to: y)
        }
    }

    /// Scrolls the text to offset `y` on the `Motion.standard` spring (at once under Reduce Motion).
    private func scrollText(to y: CGFloat) {
        guard let sv = webView?.scrollView else { return }
        let offset = CGPoint(x: sv.contentOffset.x, y: y)
        guard animates else { return sv.contentOffset = offset }
        UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            sv.contentOffset = offset
        }
    }

    /// The fragment of `url` when it points into the page at `page` (only its fragment differs).
    /// Read from the string: `URL.fragment` is nil for the reading page's `about:blank#…`.
    private static func fragment(of url: URL, on page: URL?) -> String? {
        let parts = url.absoluteString.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty, let page,
              parts[0] == page.absoluteString.split(separator: "#", omittingEmptySubsequences: false)[0]
        else { return nil }
        return String(parts[1])
    }
}
