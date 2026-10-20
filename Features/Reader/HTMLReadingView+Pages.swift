import SwiftUI
import WebKit

/// Pages mode (the reading appearance's `ReadingLayout.pages`, in a reading sheet): the text shows
/// one page of whole lines at a time.
///
/// - The page is laid out in CSS columns, one per screen width, from the top inset (under the top
///   bar) down to the footer; WebKit breaks lines between columns, so no line is ever cut.
/// - The line being read stays on screen through every new layout (loading, a reflow from Aa or
///   Dynamic Type, an image arriving: the script's `ResizeObserver` posts `layout`): the page
///   holding the first character of the page shown (`start`) is shown again.
/// - Pages turn sideways with native paging (C107, see `PagesTextLayout`): the page tracks the
///   finger and settles with the system's physics; an edge tap slides one page. The leftmost
///   `ReadingChrome.TapZone.edgeMargin` points are left to the system (back).
/// - Pages never follow the audio (C108): the page you read stays until you turn it. *Jump to
///   Audio* (above the band, bars shown: C111) goes to the spoken sentence's page once.
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
    fileprivate(set) var start: Spot?
    /// The first character of the next page (nil on the last page or until looked up).
    fileprivate(set) var end: Spot?

    fileprivate func reset() {
        shown = nil
        start = nil
        end = nil
    }
}

extension ReadingPages.Spot: Comparable {
    static func < (a: Self, b: Self) -> Bool {
        (a.paragraph, a.offset) < (b.paragraph, b.offset)
    }

    /// The spoken sentence's first character (its paragraph's, before the sentence is known).
    init(_ spoken: (paragraph: Int, sentence: ReaderSentence?)) {
        self.init(paragraph: spoken.paragraph, offset: spoken.sentence?.start ?? 0)
    }
}

/// Pages mode's layout (see `ReadingPages`), C107: the page's own CSS columns, one per screen
/// width, in the web view's scroll view with native paging, as Apple Books' Slide. The body is a
/// column box from the top inset (under the top bar) down to the footer; WebKit breaks lines
/// between columns, so no line is ever cut. Pages track the finger 1:1 and settle with UIKit's
/// paging physics; an edge tap slides one page with the scroll view's own animation. A strip
/// `edgeGuard` wide at the left edge takes no part in paging: the system's swipe back stays free.
@MainActor
final class PagesTextLayout: NSObject, ReadingTextLayout {
    private unowned let host: HTMLReadingWebView.Coordinator
    /// What the footer shows.
    let model: ReadingPages
    /// The room under the pages: the footer and the home indicator's inset.
    private var footer: CGFloat
    private var insets = ReaderTextInsets()
    /// The column layout is on the page.
    private var paged = false
    /// A measurement in flight, and another asked for meanwhile.
    private var measuring = false
    private var remeasure = false
    /// The spot the next measurement keeps on screen (a hand-over, the mode switch); else the
    /// page's start, else the hold's.
    private var keep: ReadingPages.Spot?
    private var offsetObservation: NSKeyValueObservation?
    private var guardView: UIView?
    /// The width a page is (the scroll view's width when it was measured).
    private var pageWidth: CGFloat = 0
    /// The bars show: the page is a card between them (C113).
    private var overview = false
    var isOverview: Bool { paged && overview }
    /// The overview's page cards (C116), by page: the shown page and its neighbours.
    private var cards: [Int: UIView] = [:]

    static let edgeGuard = ReadingChrome.TapZone.edgeMargin

    init(host: HTMLReadingWebView.Coordinator, model: ReadingPages, footer: CGFloat) {
        self.host = host
        self.model = model
        self.footer = footer
    }

    private var scrollView: UIScrollView? { host.webView?.scrollView }

    /// Scroll mode handed over: the line at the top of the reading area is kept.
    func activate() {
        guard let sv = scrollView, host.loaded else { return }
        reset()
        let y = sv.contentOffset.y + sv.contentInset.top
        anchor(atDocumentY: y) { [weak self] spot in
            self?.keep = spot
            self?.paginate()
        }
    }

    func setFooter(_ footer: CGFloat) {
        guard footer != self.footer else { return }
        self.footer = footer
        if paged { applyColumns() }
    }

    func reset() {
        model.reset()
        keep = nil
        remeasure = false
    }

    func opened() {
        model.reset()
        // A hand-over is placed from the single column first (`open(handOver:)`).
        if case .handOver(.text) = host.hold { return }
        keep = nil
        paginate()
    }

    func open(handOver: ReadingHandOver) {
        guard case .text(let offset) = handOver, let webView = host.webView else {
            host.handOverPlaced()
            return paginate()
        }
        anchor(atDocumentY: host.documentY(of: offset, in: webView)) { [weak self] spot in
            self?.keep = spot
            self?.host.handOverPlaced()
            self?.paginate()
        }
    }

    /// Pages never place by document y: the spoken sentence and a scrub go through `show(spot:)`.
    func show(top: CGFloat, height: CGFloat, _ placement: ReadingPlacement) -> Bool { true }

    /// The page holding `spot`, at once.
    func show(spot: ReadingPages.Spot) {
        guard paged, let webView = host.webView, pageWidth > 0 else { keep = spot; return }
        let generation = host.loadGeneration
        webView.evaluateJavaScript("window.__readerSpotPage(\(spot.paragraph), \(spot.offset), \(Double(pageWidth)))") {
            [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self, let page = result as? Int else { return }
            // Until the new page's first character is known, the voice isn't taken as elsewhere.
            if page != model.shown?.index { model.start = nil; model.end = nil }
            show(page: page, animated: false)
        }
    }

    /// The page holding a same-page link's target.
    func show(fragment: String) {
        guard paged, let webView = host.webView, pageWidth > 0,
              let data = try? JSONSerialization.data(withJSONObject: [fragment]),
              let arg = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__readerFragmentPage(\(arg)[0], \(Double(pageWidth)))") { [weak self] result, _ in
            guard let self, host.layout === self, let page = result as? Int else { return }
            show(page: page, animated: host.animates)
        }
    }

    /// Pages never follow the audio (C108): once the voice leaves the page shown, following stops
    /// (Now Playing then offers *Jump to Audio* above the band, C111).
    func follow(word: ReadingPages.Spot) {
        guard let start = model.start, model.shown != nil else { return }
        if word < start || model.end.map({ word >= $0 }) == true { host.stopFollowing() }
    }

    func turn(forward: Bool) -> Bool {
        guard let shown = model.shown else { return false }
        let index = shown.index + (forward ? 1 : -1)
        guard (0..<shown.count).contains(index) else { return false }
        show(page: index, animated: host.animates)
        return true
    }

    /// Kindle-style overview (C113): with the bars shown the page laid out for reading shrinks
    /// into a card (`ReadingPagesCard`, a SwiftUI scale: no reflow); here the neighbours are let
    /// out of the scroll view's clip so they peek either side. Taps on the card zoom back.
    func setOverview(_ on: Bool) {
        guard on != overview else { return }
        overview = on
        applyOverview()
        updateCards(animated: true)
        if on { repaint() }
    }

    /// The overview's cards (C116, Kindle's): each page's own rectangle, inset `cardGap` from its
    /// column's edges (inside the page margin, so the text never moves) so a gap parts the cards;
    /// the shown page outlined in the theme's accent, its neighbours in the theme's rule (a quiet
    /// grey fitted to each reading theme). They scroll with the pages, so the selection follows
    /// the page centred; hidden while reading.
    static let cardGap = Spacing.s

    private func updateCards(animated: Bool) {
        guard let sv = scrollView else { return }
        guard paged, let shown = model.shown, pageWidth > 0 else {
            cards.values.forEach { $0.removeFromSuperview() }
            cards = [:]
            return
        }
        let wanted = Set(max(0, shown.index - 2)...min(shown.count - 1, shown.index + 2))
        for (i, card) in cards where !wanted.contains(i) {
            card.removeFromSuperview()
            cards[i] = nil
        }
        let colors = host.look.colors
        let accent = Self.color(colors.accent), rule = Self.color(colors.rule)
        let alpha: CGFloat = overview ? 1 : 0
        for i in wanted {
            let card = cards[i] ?? {
                let v = UIView()
                v.isUserInteractionEnabled = false
                v.backgroundColor = .clear
                v.alpha = 0
                v.accessibilityIdentifier = "readingPageCard"
                sv.addSubview(v)
                cards[i] = v
                return v
            }()
            card.frame = CGRect(x: CGFloat(i) * pageWidth + Self.cardGap, y: 0,
                                width: pageWidth - 2 * Self.cardGap, height: sv.bounds.height)
            let current = i == shown.index
            card.layer.borderColor = (current ? accent : rule).cgColor
            card.layer.borderWidth = current ? 2 : 1.5
            sv.bringSubviewToFront(card)
            card.alpha = alpha
            card.isHidden = !overview
        }
    }

    /// The neighbours drawn outside the screen can keep tiles from an earlier layout (C116): a
    /// repaint of the body, now and once the layout has settled, clears them.
    private func repaint() {
        guard let webView = host.webView else { return }
        let js = "(function(){var b=document.body;b.style.opacity='0.999';requestAnimationFrame(function(){b.style.opacity='';});})()"
        webView.evaluateJavaScript(js, completionHandler: nil)
        Task { @MainActor [weak webView] in
            try? await Task.sleep(for: .milliseconds(400))
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// A new theme: the cards' outlines in its colours.
    func lookChanged() {
        updateCards(animated: false)
        repaint()
    }

    private static func color(_ hex: String) -> UIColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private func applyOverview() {
        guard let webView = host.webView else { return }
        // Never clipped in Pages (C114): the neighbours stay drawn, so the card never shows blank
        // while they come into view; off screen while reading.
        webView.clipsToBounds = !paged
        webView.scrollView.clipsToBounds = !paged
    }

    func setInsets(_ insets: ReaderTextInsets) {
        self.insets = insets
        guard let sv = scrollView else { return }
        sv.verticalScrollIndicatorInsets = .zero
        if paged { applyColumns() } else { sv.contentInset = .zero }
    }

    func reflowAnchor() -> (y: CGFloat, atTop: Bool) { (0, false) }

    func reflowed(_ reflow: ReadingReflow, atTop: Bool) {
        measure()
    }

    func contentChanged() {
        if paged { measure() }
    }

    func viewportLaidOut() {
        guard paged, let sv = scrollView, sv.bounds.width > 0, sv.bounds.width != pageWidth else { return }
        applyColumns()
    }

    /// Back to Scroll mode: one column again, the page's first line at the top of the reading area.
    func deactivate() {
        let start = model.start
        model.reset()
        offsetObservation = nil
        guardView?.removeFromSuperview()
        guardView = nil
        host.topViewY = 0
        guard let webView = host.webView else { return }
        let sv = webView.scrollView
        webView.clipsToBounds = true
        sv.clipsToBounds = true
        cards.values.forEach { $0.removeFromSuperview() }
        cards = [:]
        sv.isPagingEnabled = false
        sv.alwaysBounceVertical = true
        sv.alwaysBounceHorizontal = false
        sv.showsVerticalScrollIndicator = true
        paged = false
        guard host.loaded else { return }
        let locate = start.map { "window.__readerSpokenRect(\($0.paragraph), \($0.offset), \($0.offset + 1))" } ?? "null"
        webView.evaluateJavaScript("window.__readerPaged(false, 0, 0); \(locate)") { [weak sv] result, _ in
            guard let sv else { return }
            sv.contentInset.right = 0
            sv.contentOffset.x = 0
            if let rect = result as? [Double], let top = rect.first {
                sv.contentOffset.y = sv.readingLayout.clamped(CGFloat(top) - sv.contentInset.top)
            }
        }
    }

    // MARK: Columns

    /// The spot (paragraph, offset) on the line at document y `y` of the single column.
    private func anchor(atDocumentY y: CGFloat, then: @escaping (ReadingPages.Spot?) -> Void) {
        guard let webView = host.webView else { return then(nil) }
        let generation = host.loadGeneration
        webView.evaluateJavaScript("window.__readerAnchor(\(Double(y)))") { [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self else { return }
            then(Self.spot(result))
        }
    }

    /// Turns the column layout on: paging on, the edge guard in, then the columns.
    private func paginate() {
        guard let webView = host.webView, host.loaded else { return }
        let sv = webView.scrollView
        paged = true
        sv.isPagingEnabled = true
        sv.alwaysBounceVertical = false
        sv.alwaysBounceHorizontal = true
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.isDirectionalLockEnabled = true
        if guardView == nil {
            let strip = UIView()
            strip.backgroundColor = .clear
            strip.isAccessibilityElement = false
            webView.addSubview(strip)
            guardView = strip
        }
        layoutGuard()
        overview = host.chrome.map { !$0.hidden } ?? false
        applyOverview()
        offsetObservation = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            MainActor.assumeIsolated { self?.offsetChanged(sv) }
        }
        applyColumns()
    }

    private func layoutGuard() {
        guard let webView = host.webView else { return }
        guardView?.frame = CGRect(x: 0, y: 0, width: Self.edgeGuard, height: webView.bounds.height)
    }

    /// The column box: from the top inset to the footer, a screen wide per page.
    private func applyColumns() {
        guard paged, let webView = host.webView else { return }
        let sv = webView.scrollView
        let width = sv.bounds.width, height = sv.bounds.height
        guard width > 0, height > 0 else { return }
        pageWidth = width
        layoutGuard()
        sv.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: sv.contentInset.right)
        // The page is the full screen inside the safe area (C113, superseding C112's area): the
        // bars hide while reading; when they show, the same page shrinks into a card between them
        // (`setOverview`), so it never reflows. A margin of `Spacing.s` above and below; the
        // columns end on whole lines.
        // The web view already starts below the status bar (the sheet's top): a small margin
        // only (C114; C113 added the status bar twice).
        let top = Spacing.m
        let bottom = footer + Spacing.s
        let boxHeight = Int(max(height - bottom, top + 100))
        let topValue = Int(top.rounded())
        host.topViewY = top
        webView.evaluateJavaScript("window.__readerPaged(true, \(topValue), \(boxHeight));") { [weak self] _, _ in
            self?.measure()
        }
    }

    /// Counts the pages and shows the one holding the line to keep.
    private func measure() {
        guard paged, host.layout === self, host.loaded, let webView = host.webView, pageWidth > 0 else { return }
        guard !measuring else { return remeasure = true }
        measuring = true
        let w = Double(pageWidth)
        let target = keep ?? model.start ?? host.heldSpot
        let spotPage = target.map { "window.__readerSpotPage(\($0.paragraph), \($0.offset), \(w))" } ?? "-1"
        let generation = host.loadGeneration
        webView.evaluateJavaScript("[document.documentElement.scrollWidth, \(spotPage)]") { [weak self] result, _ in
            guard let self else { return }
            measuring = false
            guard generation == host.loadGeneration, host.layout === self, paged else { return }
            if remeasure { remeasure = false; return measure() }
            guard let parts = result as? [Any], parts.count == 2, let scrollWidth = parts[0] as? Double else { return }
            let sv = webView.scrollView
            let count = max(1, Int((CGFloat(scrollWidth) / pageWidth).rounded(.up)))
            // The content reaches a whole number of pages, so the last one pages into place.
            let right = max(0, CGFloat(count) * pageWidth - sv.contentSize.width)
            if abs(sv.contentInset.right - right) > 0.5 { sv.contentInset.right = right }
            let page = (parts[1] as? Int).flatMap { $0 >= 0 ? $0 : nil } ?? model.shown?.index ?? 0
            keep = nil
            model.shown = ReadingPages.Shown(index: min(page, count - 1), count: count, visibleTop: 0,
                                             visibleBottom: sv.bounds.height)
            show(page: page, animated: false)
            host.placeHold()
            repaint()
        }
    }

    /// Shows page `index` (clamped): its column at the scroll view's left edge.
    private func show(page index: Int, animated: Bool) {
        guard let sv = scrollView, let shown = model.shown, pageWidth > 0 else { return }
        let i = min(max(index, 0), shown.count - 1)
        let offset = CGPoint(x: CGFloat(i) * pageWidth, y: 0)
        if sv.contentOffset != offset { sv.setContentOffset(offset, animated: animated) }
        pageShown(i)
    }

    /// The scroll view moved (a swipe, a slide): the page under it once it rests on one.
    private func offsetChanged(_ sv: UIScrollView) {
        guard paged, pageWidth > 0, let shown = model.shown else { return }
        if abs(sv.contentOffset.y) > 0.5 { sv.contentOffset.y = 0 }
        let exact = sv.contentOffset.x / pageWidth
        let index = Int(exact.rounded())
        guard abs(exact - CGFloat(index)) < 0.01, index != shown.index else { return }
        if sv.isTracking || sv.isDecelerating {
            host.userTookOver()
            host.stopFollowing()
            host.chrome?.revealFloatingControl()
        }
        pageShown(index)
    }

    /// Page `index` is on screen: the footer, and its first character.
    private func pageShown(_ index: Int) {
        guard let shown = model.shown, let webView = host.webView else { return }
        let i = min(max(index, 0), shown.count - 1)
        if shown.index != i { model.shown?.index = i }
        updateCards(animated: false)
        let generation = host.loadGeneration
        let w = Double(pageWidth)
        webView.evaluateJavaScript("[window.__readerPageStart(\(i), \(w)), window.__readerPageStart(\(i + 1), \(w))]") {
            [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self, model.shown?.index == i,
                  let parts = result as? [Any], parts.count == 2 else { return }
            if let spot = Self.spot(parts[0]) { model.start = spot }
            model.end = i + 1 < (model.shown?.count ?? 0) ? Self.spot(parts[1]) : nil
        }
    }

    private static func spot(_ anchor: Any?) -> ReadingPages.Spot? {
        guard let a = anchor as? [String: Any], let paragraph = a["index"] as? Int, paragraph >= 0 else { return nil }
        return ReadingPages.Spot(paragraph: paragraph, offset: a["offset"] as? Int ?? 0)
    }
}

/// What Pages mode draws over the text: the page's colour above and below the page shown, and
/// the footer at the foot, above the home indicator: "Page 3 of 9   2 min left" (a chapter's says
/// "2 min left in chapter"), the parts set apart by space (`DetailLine`). It takes no touches:
/// taps reach the text under it.
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
            // Kindle's (C113): the time left on the left, how far through on the right; only while
            // reading (the bars show the player instead).
            HStack {
                Text(pages.start.flatMap { timeLeft($0.paragraph, $0.offset) } ?? " ")
                Spacer()
                Text(shown.map { "\(Int((Double($0.index + 1) / Double(max($0.count, 1)) * 100).rounded()))%" } ?? "")
            }
                .typeStyle(.caption)
                .padding(.horizontal, Spacing.l)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.xxs)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chrome?.pageFooter = $0 }
                .onDisappear { chrome?.pageFooter = 0 }
                .padding(.bottom, chrome?.homeIndicator ?? 0)
                .opacity(shown == nil || chrome?.hidden != true ? 0 : 1)
                .animation(Motion.standard, value: chrome?.hidden == true)
                .accessibilityIdentifier("readingPageFooter")
        }
        .allowsHitTesting(false)
    }
}

/// Pages' overview (C113, Kindle's): while the bars show, the page laid out for the full screen
/// shrinks (a scale, so it never reflows) into a card centred between them, outlined in the
/// accent, the neighbouring pages peeking either side; hidden bars zoom it back to full screen.
/// A spring; under Reduce Motion a short fade instead of the zoom.
struct ReadingPagesCard: ViewModifier {
    let active: Bool
    let overview: Bool
    let insets: ReaderTextInsets

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fade = 1.0

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let room = h - insets.top - insets.bottom - 2 * Spacing.m
            let scale = active && overview && h > 0 ? min(0.78, max(0.4, room / h)) : 1
            let centre = insets.top + Spacing.m + room / 2
            content
                .scaleEffect(scale)
                .offset(y: scale < 1 ? centre - h / 2 : 0)
                .opacity(fade)
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12), value: scale)
        }
        .onChange(of: active && overview) {
            guard reduceMotion else { return }
            fade = 0.2
            withAnimation(.easeOut(duration: 0.25)) { fade = 1 }
        }
    }
}
