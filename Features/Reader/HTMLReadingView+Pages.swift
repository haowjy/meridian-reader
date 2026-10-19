import SwiftUI
import WebKit

/// Pages mode (the reading appearance's `ReadingLayout.pages`, in a reading sheet): the text shows
/// one page of whole lines at a time.
///
/// - The page's script measures its lines (`__readerLines`); `ReadingPagination` breaks them into
///   pages as tall as the reading area: from the top inset (under the top bar) down to the footer.
///   Page k shows with its top at the top inset; native views in the page's colour
///   (`ReadingPageFrame`) cover whatever of the pages around it would show, so no line is ever
///   cut. The bars hide and show over it as in Scroll mode; the band covers the footer.
/// - The line being read stays on screen through every new layout (loading, a reflow from Aa or
///   Dynamic Type, the title card's height, an image arriving: the script's `ResizeObserver`
///   posts `layout`): the page holding the first character of the page shown (`start`) is shown
///   again, or, following the audio, the page holding the spoken sentence.
/// - A tap at either edge turns one page at once; a vertical drag turns one page its way and
///   snaps there on release, on the `Motion.standard` spring. A pull down on the first page
///   behaves as at the top in Scroll mode (the scroll view's own pull hand-off).
/// - Following the audio turns to the page holding the spoken sentence when the voice reaches it;
///   a turn by the user stops following (Jump to Audio resumes it), as a drag does in Scroll
///   mode.
@MainActor
@Observable
final class ReadingPages {
    /// A character in the text: its listen paragraph and the UTF-16 offset in it.
    struct Spot: Equatable {
        var paragraph: Int
        var offset: Int
    }

    /// The page shown, of `count`, and the part of the web view (its own y) it takes: the page's
    /// colour covers the text above `visibleTop` and below `visibleBottom`.
    struct Shown: Equatable {
        var index: Int
        var count: Int
        var visibleTop: CGFloat
        var visibleBottom: CGFloat
    }

    /// Nil until the page is paginated.
    fileprivate(set) var shown: Shown?
    /// The first character of the page shown: what the footer counts the time left from, and the
    /// line a new layout keeps on screen. Nil: the top of the text.
    var start: Spot?

    @ObservationIgnored fileprivate(set) var pagination: ReadingPagination?
    /// A measurement in flight, another asked for meanwhile, and whether either goes to the spoken
    /// sentence once laid out.
    @ObservationIgnored fileprivate var measuring = false
    @ObservationIgnored fileprivate var remeasure = false
    @ObservationIgnored var follow = false
    /// The web view's height the pages were broken for.
    @ObservationIgnored fileprivate var viewportHeight: CGFloat = 0

    /// A new page loads: nothing measured.
    func reset() {
        shown = nil
        start = nil
        pagination = nil
        remeasure = false
        follow = false
    }
}

extension ReadingPages.Spot {
    /// The spoken sentence's first character (its paragraph's, before the sentence is known).
    init(_ spoken: (paragraph: Int, sentence: ReaderSentence?)) {
        self.init(paragraph: spoken.paragraph, offset: spoken.sentence?.start ?? 0)
    }
}

extension HTMLReadingWebView.Coordinator {
    /// Scroll ↔ Pages, live (and the room under the pages): the line at the top of the reading
    /// area stays there.
    func setPages(_ model: ReadingPages?, footer: CGFloat) {
        let footerChanged = footer != pageFooter
        pageFooter = footer
        guard model !== pages else {
            if footerChanged { measurePages() }
            return
        }
        pages = model
        guard let webView else { return }
        let sv = webView.scrollView
        sv.showsVerticalScrollIndicator = model == nil
        // A load in flight opens in the new mode (`didFinish`).
        guard loaded else { return }
        cancelRestore()
        guard let model else { return relayOut() }
        model.reset()
        // Following goes back to the spoken sentence once paged.
        model.follow = true
        guard sv.contentOffset.y > -sv.contentInset.top + 1 else { return relayOut() }
        startPages(atLineAt: sv.contentOffset.y + sv.contentInset.top, then: relayOut)
    }

    /// The insets and the room under the text again, for the mode now on (which then measures the
    /// pages).
    private func relayOut() {
        sentInsets = nil
        setTextInsets(textInsets)
        if pages == nil { setPageRoom() }
    }

    /// The page loaded in Pages mode: it opens on the handed-over line (D2), a scrub's paragraph,
    /// the spoken sentence (following, or the Reader's saved spot), else the first page.
    func openPages() {
        guard let pages, let webView else { return }
        pages.reset()
        webView.scrollView.contentOffset = CGPoint(x: 0, y: -textInsets.top)
        if opensAt != nil {
            // Handed over from the Reader (D2): the page holding the line it had at the top of
            // its reading area.
            return measureTextTop { [weak self] in
                guard let self, let webView = self.webView, let handOver = opensAt else { return }
                opensAt = nil
                guard case .text(let offset) = handOver else { return measurePages() }
                let sv = webView.scrollView
                startPages(atLineAt: textTop + max(0, viewportTop(of: webView) + sv.contentInset.top + offset))
            }
        }
        if let index = pendingScrollIndex {
            pendingScrollIndex = nil
            pages.start = ReadingPages.Spot(paragraph: index, offset: 0)
        } else {
            goToSpoken(.jump)
        }
        measurePages()
    }

    /// Pages from the line at document y `y`: it becomes the page's `start`, then `then` runs
    /// (by default, measuring the pages).
    private func startPages(atLineAt y: CGFloat, then: (() -> Void)? = nil) {
        guard let webView else { return }
        let generation = loadGeneration
        webView.evaluateJavaScript("window.__readerAnchor(\(Double(y)))") { [weak self] result, _ in
            guard let self, generation == loadGeneration, let pages else { return }
            pages.start = Self.spot(result)
            if let then { then() } else { measurePages() }
        }
    }

    /// Measures the lines and breaks them into pages again, then shows the page holding `start`
    /// (and, with `follow`, goes to the spoken sentence while the text goes there). One at a
    /// time: a request during one runs once it is back.
    func measurePages(follow: Bool = false) {
        guard let pages, let webView, loaded, webView.scrollView.bounds.height > 0 else { return }
        pages.follow = pages.follow || follow
        guard !pages.measuring else { return pages.remeasure = true }
        pages.measuring = true
        pages.viewportHeight = webView.scrollView.bounds.height
        let generation = loadGeneration
        let requested = pages.start
        let held = requested.map { "window.__readerSpokenRect(\($0.paragraph), \($0.offset), \($0.offset + 1))" }
        webView.evaluateJavaScript("[window.__readerLines(), \(held ?? "null")]") { [weak self] result, _ in
            pages.measuring = false
            guard let self, generation == loadGeneration, self.pages === pages else { return }
            // Asked again meanwhile, or the line to keep changed: this one is stale.
            guard !pages.remeasure, pages.start == requested else {
                pages.remeasure = false
                return measurePages()
            }
            guard let parts = result as? [Any], parts.count == 2, let flat = parts[0] as? [Double] else { return }
            let sv = webView.scrollView
            let lines = stride(from: 0, to: flat.count - 1, by: 2).map {
                ReadingPagination.Line(top: CGFloat(flat[$0]), bottom: CGFloat(flat[$0 + 1]))
            }
            let height = sv.bounds.height - sv.contentInset.top - pageFooter
            guard height > 0 else { return }
            let pagination = ReadingPagination(lines: lines, pageHeight: height, margin: Spacing.xs)
            pages.pagination = pagination
            let heldTop = (parts[1] as? [Double])?.first.map { CGFloat($0) } ?? 0
            show(page: pagination.index(holding: heldTop))
            if pages.follow {
                pages.follow = false
                goToSpoken(.jump)
            }
        }
    }

    /// Pages: room below the text, a screen tall, so the last page's top can reach the top of the
    /// reading area. Padding on the page rather than a scroll inset: a tap there lands on the
    /// page's body, which takes taps (an inset is outside the document, and gets none). Scroll
    /// mode takes it away. Laying the page out again measures the pages again.
    func setPageRoom() {
        guard let webView, loaded else { return }
        let room = pages == nil ? 0 : webView.scrollView.bounds.height
        guard room != pageRoom else { return measurePages() }
        pageRoom = room
        webView.evaluateJavaScript("document.body.style.setProperty('--page-room', '\(Int(room))px');") { [weak self] _, _ in
            guard let self else { return }
            guard pages == nil else { return measurePages() }
            // Back in Scroll mode: the text stays where it is, within what it can scroll to.
            let sv = webView.scrollView
            let layout = ReadingScrollRestore.Layout(
                contentHeight: sv.contentSize.height, viewportHeight: sv.bounds.height,
                insetTop: sv.contentInset.top, insetBottom: sv.contentInset.bottom)
            let y = min(max(sv.contentOffset.y, layout.range.lowerBound), layout.range.upperBound)
            if y != sv.contentOffset.y { sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: y) }
        }
    }

    /// The web view's height changed (the sheet laid out): break the pages again for it.
    func layoutPages() {
        guard let pages, let sv = webView?.scrollView, sv.bounds.height != pages.viewportHeight else { return }
        sentInsets = nil
        setTextInsets(textInsets)
    }

    /// Shows page `index` (clamped): its top at the top of the reading area, at once or on the
    /// spring, the pages around it covered; then looks up its first character.
    func show(page index: Int, animated: Bool = false) {
        guard let pages, let pagination = pages.pagination, let webView else { return }
        let i = min(max(index, 0), pagination.pages.count - 1)
        let page = pagination.pages[i]
        let sv = webView.scrollView
        let y = page.top - sv.contentInset.top
        pages.shown = ReadingPages.Shown(index: i, count: pagination.pages.count, visibleTop: page.visibleTop - y,
                                         visibleBottom: page.visibleBottom - y)
        // Stops a deceleration or bounce the scroll view has begun.
        sv.setContentOffset(sv.contentOffset, animated: false)
        let offset = CGPoint(x: sv.contentOffset.x, y: y)
        if animated, animates {
            UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                sv.contentOffset = offset
            }
        } else {
            sv.contentOffset = offset
        }
        // Unless something else (a hand-over, the mode switch) sets the line to keep meanwhile.
        let generation = loadGeneration, before = pages.start
        webView.evaluateJavaScript("window.__readerAnchor(\(Double(page.top)))") { [weak self] result, _ in
            guard let self, generation == loadGeneration, self.pages === pages, pages.shown?.index == i,
                  pages.start == before, let spot = Self.spot(result) else { return }
            pages.start = spot
        }
    }

    /// The page holding document y `y`, unless it shows already (following the audio).
    func showPage(holding y: CGFloat) {
        guard let pages, let pagination = pages.pagination else { return }
        let index = pagination.index(holding: y)
        if index != pages.shown?.index { show(page: index) }
    }

    /// The page holding paragraph `index`'s start (following a scrub).
    func showPage(holdingParagraph index: Int) {
        guard let webView else { return }
        let generation = loadGeneration
        webView.evaluateJavaScript("window.__readerSpokenRect(\(index), null, null)") { [weak self] result, _ in
            guard let self, generation == loadGeneration, let rect = result as? [Double], let top = rect.first else { return }
            showPage(holding: CGFloat(top))
        }
    }

    /// A tap at an edge: the next or previous page, at once. The user moved the text: following
    /// stops.
    func turnPage(forward: Bool) {
        guard let shown = pages?.shown else { return }
        let index = shown.index + (forward ? 1 : -1)
        guard (0..<shown.count).contains(index) else { return }
        userTookOver()
        stopFollowing()
        show(page: index)
    }

    /// A drag on the text let go (`velocity` down positive): one page its way, or back to the
    /// page it began on when it moved too little.
    func pageDragEnded(velocity: CGFloat) {
        guard let pages, let shown = pages.shown, let pagination = pages.pagination, let sv = webView?.scrollView
        else { return }
        let moved = sv.contentOffset.y - (pagination.pages[shown.index].top - sv.contentInset.top)
        let step = if abs(velocity) > Self.pageFlick { velocity < 0 ? 1 : -1 }
            else if abs(moved) > Self.pageDrag { moved > 0 ? 1 : -1 }
            else { 0 }
        show(page: shown.index + step, animated: true)
    }

    /// How far a drag moves the text, or how fast it lets go (points per second), to turn a page.
    private static let pageDrag: CGFloat = 24
    private static let pageFlick: CGFloat = 300

    private static func spot(_ anchor: Any?) -> ReadingPages.Spot? {
        guard let a = anchor as? [String: Any], let paragraph = a["index"] as? Int, paragraph >= 0 else { return nil }
        return ReadingPages.Spot(paragraph: paragraph, offset: a["offset"] as? Int ?? 0)
    }
}

/// What Pages mode draws over the text: the page's colour above and below the page shown, and
/// the footer at the foot, above the home indicator: "Page 3 of 9   2 min left in chapter", the
/// parts set apart by space (`DetailLine`). It takes no touches: taps reach the text under it.
/// Its height goes to the chrome (`pageFooter`), so what floats over the text sits above it.
struct ReadingPageFrame: View {
    let pages: ReadingPages
    let palette: ReadingPalette
    let timeLeft: (_ paragraph: Int, _ offset: Int) -> String?

    @Environment(\.readingChrome) private var chrome

    var body: some View {
        let shown = pages.shown
        ZStack(alignment: .top) {
            if let shown {
                palette.background
                    .frame(height: max(0, shown.visibleTop))
                palette.background
                    .padding(.top, max(0, shown.visibleBottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            DetailLine([shown.map { String(localized: "Page \($0.index + 1) of \($0.count)") },
                        pages.start.flatMap { timeLeft($0.paragraph, $0.offset) }])
                .typeStyle(.caption)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.xs)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chrome?.pageFooter = $0 }
                .onDisappear { chrome?.pageFooter = 0 }
                .padding(.bottom, chrome?.homeIndicator ?? 0)
                .opacity(shown == nil ? 0 : 1)
                .accessibilityIdentifier("readingPageFooter")
        }
        .allowsHitTesting(false)
    }
}
