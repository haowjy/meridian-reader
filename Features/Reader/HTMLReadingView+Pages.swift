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
///   again, or the one holding what the coordinator holds (`heldSpot`: the spoken sentence while
///   the text goes there, a scrubbed paragraph).
/// - Following the audio, the page holding the spoken sentence shows, and the page turns when the
///   spoken word reaches the next page's first character (`nextStart`), so a sentence running
///   over a page break turns the page as the voice crosses it.
/// - Pages turn sideways, as in a book (C106): a horizontal swipe drags the page shown off its
///   side, the next (swiping left) or the previous (right) already under it, and lets go past a
///   quarter of the width (or flicked) to turn, else springs back; a tap at either edge zone
///   slides one page the same way (at once under Reduce Motion). The text never scrolls
///   vertically here. A swipe that begins in the leftmost `ReadingChrome.TapZone.edgeMargin`
///   points is left to the system (back), as the left edge zone's taps are.
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

    fileprivate func reset() {
        shown = nil
        start = nil
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

/// Pages mode's layout (see `ReadingPages`).
@MainActor
final class PagesTextLayout: ReadingTextLayout {
    private unowned let host: HTMLReadingWebView.Coordinator
    /// What the page frame and the footer show.
    let model: ReadingPages
    /// The room under the pages: the footer and the home indicator's inset.
    private var footer: CGFloat
    private var pagination: ReadingPagination?
    /// A measurement in flight, another asked for meanwhile, and whether either puts the
    /// coordinator's hold back once laid out.
    private var measuring = false
    private var remeasure = false
    private var placesHold = false
    /// The web view's height the pages were broken for.
    private var viewportHeight: CGFloat = 0
    /// The room the page has below its text for the last page to reach the top.
    private var room: CGFloat = 0
    /// The first character of the page after the one shown; nil on the last page, or until
    /// looked up.
    private var nextStart: ReadingPages.Spot?

    init(host: HTMLReadingWebView.Coordinator, model: ReadingPages, footer: CGFloat) {
        self.host = host
        self.model = model
        self.footer = footer
    }

    private var scrollView: UIScrollView? { host.webView?.scrollView }

    /// Scroll mode handed over, the page loaded: the line at the top of the reading area stays
    /// there, or, following, the spoken sentence's page shows.
    func activate() {
        guard let sv = scrollView else { return }
        installSwipe()
        reset()
        placesHold = true
        guard sv.contentOffset.y > -sv.contentInset.top + 1 else { return host.reapplyInsets() }
        startPages(atLineAt: sv.contentOffset.y + sv.contentInset.top) { [weak self] in self?.host.reapplyInsets() }
    }

    func setFooter(_ footer: CGFloat) {
        guard footer != self.footer else { return }
        self.footer = footer
        measure(placesHold: false)
    }

    func reset() {
        model.reset()
        pagination = nil
        nextStart = nil
        remeasure = false
        placesHold = false
        room = 0
    }

    func opened() {
        guard let sv = scrollView else { return }
        installSwipe()
        model.reset()
        pagination = nil
        nextStart = nil
        sv.contentOffset = CGPoint(x: 0, y: -sv.contentInset.top)
        measure(placesHold: true)
    }

    /// The page holding the line the Reader had at the top of its reading area. It wins over the
    /// opening's measure, which would put the spoken sentence's page up.
    func open(handOver: ReadingHandOver) {
        placesHold = false
        guard case .text(let offset) = handOver, let webView = host.webView else {
            host.handOverPlaced()
            return measure(placesHold: false)
        }
        startPages(atLineAt: host.documentY(of: offset, in: webView)) { [weak self] in
            self?.host.handOverPlaced()
            self?.measure(placesHold: false)
        }
    }

    func show(top: CGFloat, height: CGFloat, _ placement: ReadingPlacement) -> Bool {
        guard let pagination else { return false }
        let index = pagination.index(holding: top)
        if index != model.shown?.index { show(page: index) }
        return true
    }

    func follow(word: ReadingPages.Spot) {
        guard let shown = model.shown, let nextStart, word >= nextStart else { return }
        show(page: shown.index + 1)
    }

    func turn(forward: Bool) -> Bool {
        guard let shown = model.shown else { return false }
        let index = shown.index + (forward ? 1 : -1)
        guard (0..<shown.count).contains(index) else { return false }
        guard host.animates, let sheet = beginSlide() else {
            show(page: index)
            return true
        }
        show(page: index)
        finishSlide(sheet, off: true, forward: forward)
        return true
    }

    // MARK: Turning sideways

    /// The horizontal swipe that turns pages (installed while Pages mode is up).
    private var swipe: PageSwipe?
    /// The swipe in progress: the page it began on, drawn as a sheet over the page it turns to.
    private var swiping: (sheet: UIView, from: Int, to: Int?)?

    /// The text stops scrolling vertically and the sideways swipe goes on the web view.
    private func installSwipe() {
        guard let webView = host.webView else { return }
        webView.scrollView.isScrollEnabled = false
        guard swipe == nil else { return }
        let swipe = PageSwipe(view: webView) { [weak self] pan in self?.swiped(pan) }
        self.swipe = swipe
    }

    /// A picture of the page shown, cut to its lines, laid over the web view: what slides away.
    private func beginSlide() -> UIView? {
        guard let webView = host.webView, let shown = model.shown,
              let picture = webView.snapshotView(afterScreenUpdates: false) else { return nil }
        let top = max(0, shown.visibleTop), bottom = min(webView.bounds.height, shown.visibleBottom)
        guard bottom > top else { return nil }
        let sheet = UIView(frame: CGRect(x: 0, y: top, width: webView.bounds.width, height: bottom - top))
        sheet.clipsToBounds = false
        let clip = UIView(frame: sheet.bounds)
        clip.clipsToBounds = true
        picture.frame.origin.y = -top
        clip.addSubview(picture)
        sheet.addSubview(clip)
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowOpacity = 0.12
        sheet.layer.shadowRadius = 6
        sheet.isUserInteractionEnabled = false
        webView.addSubview(sheet)
        return sheet
    }

    /// The sheet slides off its side (`off`: the turn holds) or back (and the page it shows
    /// returns), then goes.
    private func finishSlide(_ sheet: UIView, off: Bool, forward: Bool, back page: Int? = nil) {
        let width = sheet.bounds.width
        UIView.animate(springDuration: Motion.standardResponse, bounce: 0, options: [.allowUserInteraction]) {
            sheet.transform = off ? CGAffineTransform(translationX: forward ? -width : width, y: 0) : .identity
        } completion: { [weak self] _ in
            if !off, let page { self?.show(page: page) }
            sheet.removeFromSuperview()
        }
    }

    private func swiped(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        let tx = pan.translation(in: view).x
        switch pan.state {
        case .began:
            guard let shown = model.shown, let sheet = beginSlide() else { return }
            let forward = pan.velocity(in: view).x < 0
            let index = shown.index + (forward ? 1 : -1)
            let to = (0..<shown.count).contains(index) ? index : nil
            if let to { show(page: to) }
            swiping = (sheet, shown.index, to)
            host.userTookOver()
            host.stopFollowing()
        case .changed:
            guard let swiping else { return }
            let forward = (swiping.to ?? swiping.from) > swiping.from
            // Only the way it began; past the first or last page it barely gives.
            var x = forward ? min(tx, 0) : max(tx, 0)
            if swiping.to == nil { x = tx / 6 }
            swiping.sheet.transform = CGAffineTransform(translationX: x, y: 0)
        case .ended, .cancelled, .failed:
            guard let swiping else { return }
            self.swiping = nil
            let vx = pan.velocity(in: view).x
            guard let to = swiping.to else {
                return finishSlide(swiping.sheet, off: false, forward: true, back: nil)
            }
            let forward = to > swiping.from
            let moved = forward ? -tx : tx, speed = forward ? -vx : vx
            let turns = pan.state == .ended && (moved > view.bounds.width / 4 || speed > Self.pageFlick)
            if !host.animates {
                if !turns { show(page: swiping.from) }
                swiping.sheet.removeFromSuperview()
            } else {
                finishSlide(swiping.sheet, off: turns, forward: forward, back: turns ? nil : swiping.from)
            }
            host.chrome?.revealFloatingControl()
        default:
            break
        }
    }

    func setInsets(_ insets: ReaderTextInsets) {
        guard let sv = scrollView else { return }
        let inset = UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
        sv.contentInset = inset
        sv.verticalScrollIndicatorInsets = inset
        setRoom(sv.bounds.height)
    }

    /// The page shown when the reflow begins.
    func reflowAnchor() -> (y: CGFloat, atTop: Bool) {
        guard let sv = scrollView else { return (0, true) }
        return (sv.contentOffset.y + sv.contentInset.top, false)
    }

    func reflowed(_ reflow: ReadingReflow, atTop: Bool) {
        measure(placesHold: true)
    }

    func contentChanged() {
        measure(placesHold: false)
    }

    /// The web view's height changed (the sheet laid out): break the pages again for it.
    func viewportLaidOut() {
        guard let sv = scrollView, sv.bounds.height != viewportHeight else { return }
        host.reapplyInsets()
    }

    /// One page the drag's way, or back to the page it began on when it moved too little.
    func dragEnded(velocity: CGFloat) {
        guard let shown = model.shown, let pagination, let sv = scrollView else { return }
        let moved = sv.contentOffset.y - (pagination.pages[shown.index].top - sv.contentInset.top)
        let step = if abs(velocity) > Self.pageFlick { velocity < 0 ? 1 : -1 }
            else if abs(moved) > Self.pageDrag { moved > 0 ? 1 : -1 }
            else { 0 }
        show(page: shown.index + step, animated: true)
    }

    /// Back to Scroll mode: the room below the text goes, and the text stays where it is, within
    /// what it can scroll to.
    func deactivate() {
        model.reset()
        swipe?.remove()
        swipe = nil
        swiping?.sheet.removeFromSuperview()
        swiping = nil
        scrollView?.isScrollEnabled = true
        guard host.loaded, let webView = host.webView else { return }
        webView.evaluateJavaScript("document.body.style.setProperty('--page-room', '0px');") { [weak webView] _, _ in
            guard let sv = webView?.scrollView else { return }
            let y = sv.readingLayout.clamped(sv.contentOffset.y)
            if y != sv.contentOffset.y { sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: y) }
        }
    }

    /// How far a drag moves the text, or how fast it lets go (points per second), to turn a page.
    private static let pageDrag: CGFloat = 24
    private static let pageFlick: CGFloat = 300

    /// Pages from the line at document y `y`: it becomes the page's `start`, then `then` runs.
    private func startPages(atLineAt y: CGFloat, then: @escaping () -> Void) {
        guard let webView = host.webView else { return }
        let generation = host.loadGeneration
        webView.evaluateJavaScript("window.__readerAnchor(\(Double(y)))") { [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self else { return }
            model.start = Self.spot(result)
            then()
        }
    }

    /// Room below the text, a screen tall, so the last page's top can reach the top of the reading
    /// area. Padding on the page rather than a scroll inset: a tap there lands on the page's body,
    /// which takes taps (an inset is outside the document, and gets none). Laying the page out
    /// again measures the pages again.
    private func setRoom(_ height: CGFloat) {
        guard host.loaded, let webView = host.webView else { return }
        guard height != room else { return measure(placesHold: false) }
        room = height
        webView.evaluateJavaScript("document.body.style.setProperty('--page-room', '\(Int(height))px');") { [weak self] _, _ in
            self?.measure(placesHold: false)
        }
    }

    /// Measures the lines and breaks them into pages again, then shows the page holding the line
    /// to keep (`heldSpot` when it puts the hold back, else `start`), and puts the hold back. One
    /// at a time: a request during one runs once it is back.
    private func measure(placesHold: Bool) {
        guard host.layout === self, host.loaded, let webView = host.webView,
              webView.scrollView.bounds.height > 0 else { return }
        self.placesHold = self.placesHold || placesHold
        guard !measuring else { return remeasure = true }
        measuring = true
        viewportHeight = webView.scrollView.bounds.height
        let generation = host.loadGeneration
        let keep = keptSpot
        let held = keep.map { "window.__readerSpokenRect(\($0.paragraph), \($0.offset), \($0.offset + 1))" }
        webView.evaluateJavaScript("[window.__readerLines(), \(held ?? "null")]") { [weak self] result, _ in
            guard let self else { return }
            measuring = false
            guard generation == host.loadGeneration, host.layout === self else { return }
            // Asked again meanwhile, or the line to keep changed: this one is stale.
            guard !remeasure, keptSpot == keep else {
                remeasure = false
                return measure(placesHold: false)
            }
            guard let parts = result as? [Any], parts.count == 2, let flat = parts[0] as? [Double] else { return }
            let sv = webView.scrollView
            let lines = stride(from: 0, to: flat.count - 1, by: 2).map {
                ReadingPagination.Line(top: CGFloat(flat[$0]), bottom: CGFloat(flat[$0 + 1]))
            }
            let height = sv.bounds.height - sv.contentInset.top - footer
            guard height > 0 else { return }
            let pagination = ReadingPagination(lines: lines, pageHeight: height, margin: Spacing.xs)
            self.pagination = pagination
            let heldTop = (parts[1] as? [Double])?.first.map { CGFloat($0) } ?? 0
            show(page: pagination.index(holding: heldTop))
            if self.placesHold {
                self.placesHold = false
                host.placeHold()
            }
        }
    }

    /// The line a measurement keeps on screen.
    private var keptSpot: ReadingPages.Spot? {
        (placesHold ? host.heldSpot : nil) ?? model.start
    }

    /// Shows page `index` (clamped): its top at the top of the reading area, at once or on the
    /// spring, the pages around it covered; then looks up its first character.
    private func show(page index: Int, animated: Bool = false) {
        guard let pagination, let webView = host.webView else { return }
        let i = min(max(index, 0), pagination.pages.count - 1)
        let page = pagination.pages[i]
        let sv = webView.scrollView
        let y = page.top - sv.contentInset.top
        model.shown = ReadingPages.Shown(index: i, count: pagination.pages.count, visibleTop: page.visibleTop - y,
                                         visibleBottom: page.visibleBottom - y)
        // Stops a deceleration or bounce the scroll view has begun.
        sv.setContentOffset(sv.contentOffset, animated: false)
        let offset = CGPoint(x: sv.contentOffset.x, y: y)
        if animated, host.animates {
            UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                sv.contentOffset = offset
            }
        } else {
            sv.contentOffset = offset
        }
        // The page's first character, unless something else (a hand-over, the mode switch) sets
        // the line to keep meanwhile, and the next page's.
        let generation = host.loadGeneration, before = model.start
        let next = pagination.pages.indices.contains(i + 1)
            ? "window.__readerAnchor(\(Double(pagination.pages[i + 1].top)))" : "null"
        nextStart = nil
        webView.evaluateJavaScript("[window.__readerAnchor(\(Double(page.top))), \(next)]") { [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self, model.shown?.index == i,
                  let parts = result as? [Any], parts.count == 2 else { return }
            if model.start == before, let spot = Self.spot(parts[0]) { model.start = spot }
            nextStart = Self.spot(parts[1])
            // The voice may be there already.
            if host.follows, let word = host.spokenWord { follow(word: word) }
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

/// Pages mode's sideways swipe: a pan that begins only when it moves more across than down, and
/// not in the leftmost `ReadingChrome.TapZone.edgeMargin` points (the system's back swipe).
@MainActor
final class PageSwipe: NSObject, UIGestureRecognizerDelegate {
    private let pan = UIPanGestureRecognizer()
    private let action: (UIPanGestureRecognizer) -> Void

    init(view: UIView, action: @escaping (UIPanGestureRecognizer) -> Void) {
        self.action = action
        super.init()
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    func remove() {
        pan.view?.removeGestureRecognizer(pan)
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) { action(pan) }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let view = g.view else { return false }
        let v = pan.velocity(in: view)
        let start = pan.location(in: view).x - pan.translation(in: view).x
        return abs(v.x) > abs(v.y) && start >= ReadingChrome.TapZone.edgeMargin
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
}
