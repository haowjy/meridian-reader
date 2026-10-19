import SwiftUI
import WebKit

/// The reading page's taps and links, and what it tells the sheet's bars (`ReadingChrome`):
/// - A finger drag on the text reports its movement (`dragged(by:)`), which hides or shows the
///   bars. Programmatic scrolls (following the audio, a scrub, a restore) never report.
/// - A tap on the text that isn't on a link (the page's script posts where it landed, see
///   `bootstrapJS`): the middle toggles the bars, the right edge goes forward a screen and the
///   left back one (`ReadingChrome.TapZone`), on the `Motion.standard` spring (a jump under Reduce
///   Motion). A page turn is the user moving the text, like a drag: following the audio stops.
///   In ☝︎ jump mode taps play from a paragraph instead and nothing here runs; outside a reading
///   sheet (no chrome: Follow's preview) taps do nothing.
/// - A link opens through the owner (`onOpenLink`: the browser); the reading view itself never
///   leaves its page, except to scroll to a fragment on it.
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
            turnScreen(forward: false)
            chrome.revealFloatingControl()
        case .next:
            turnScreen(forward: true)
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
        let offset = CGPoint(x: sv.contentOffset.x, y: target)
        guard animates else { return sv.contentOffset = offset }
        UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            sv.contentOffset = offset
        }
    }

    // MARK: Links

    /// The page itself loads (the reading HTML, a reload) and embeds in it load; a link on it opens
    /// through the owner, except a fragment link on the page, which scrolls there, and a
    /// `javascript:` link, which does nothing. Nothing else takes the reading view anywhere.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.navigationType == .linkActivated || action.targetFrame == nil {
            if Self.isFragment(url, of: webView.url) { return decisionHandler(.allow) }
            decisionHandler(.cancel)
            if url.scheme?.lowercased() != "javascript" { onOpenLink(url) }
            return
        }
        // A frame inside the page (an embed) loads as it would; the page's own frame only loads
        // the reading HTML.
        let isPage = action.targetFrame?.isMainFrame != false
        decisionHandler(!isPage || url.absoluteString == "about:blank" ? .allow : .cancel)
    }

    /// `url` points into the page at `page` (only its fragment differs).
    private static func isFragment(_ url: URL, of page: URL?) -> Bool {
        guard url.fragment != nil, let page else { return false }
        func base(_ u: URL) -> String { u.absoluteString.components(separatedBy: "#")[0] }
        return base(url) == base(page)
    }
}
