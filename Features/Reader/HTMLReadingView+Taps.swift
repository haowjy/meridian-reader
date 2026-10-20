import SwiftUI
import WebKit

/// The reading page's taps and links, and what it tells the sheet's bars (`ReadingChrome`):
/// - A finger drag on the text reports its movement (`dragged(by:)`), which hides or shows the
///   bars. Programmatic scrolls (following the audio, a scrub, a restore) never report.
/// - A tap on the text that isn't on a link (the page's script posts where it landed, see
///   `bootstrapJS`): the middle toggles the bars, the right edge goes forward a screen and the
///   left back one (`ReadingChrome.TapZone`), on the `Motion.standard` spring (a jump under Reduce
///   Motion); in Pages mode a whole page, at once (`ReadingTextLayout.turn`). A page turn is the
///   user moving the text, like a drag: following the audio stops.
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
        let zone = ReadingChrome.TapZone(x: x, width: width)
        switch zone {
        case .none:
            break
        case .centre:
            chrome.tappedCentre()
        case .previous, .next:
            if layout.turn(forward: zone == .next) {
                userTookOver()
                stopFollowing()
            }
            chrome.revealFloatingControl()
        }
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
        if let pages = layout as? PagesTextLayout {
            userTookOver()
            stopFollowing()
            return pages.show(fragment: fragment)
        }
        guard loaded, let data = try? JSONSerialization.data(withJSONObject: [fragment]),
              let arg = String(data: data, encoding: .utf8) else { return }
        locate("window.__readerAnchorRect(\(arg)[0])") { [weak self] top, height in
            guard let self else { return }
            userTookOver()
            stopFollowing()
            layout.show(top: top, height: height, .top)
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
