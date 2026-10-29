import SwiftUI
import WebKit

/// What `HTMLReadingView` shows in its web view and when: the page's state (`hold`, the spoken
/// sentence, a scrub, a link) and the bridge to its script. The layout it hands the text to
/// (`ReadingTextLayout`) is in `HTMLReadingView+Scroll.swift` and `+Pages.swift`; taps and links
/// in `+Taps.swift`; the page and its script in `+Script.swift`.
extension HTMLReadingWebView {
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTapParagraph: (Int) -> Void
        var onPlaySelection: ((_ paragraph: Int, _ offset: Int) -> Void)?

        /// *Play from Here* (C109): the selection's start, then the owner plays from its sentence.
        func playFromSelection() {
            guard let webView, let onPlaySelection else { return }
            webView.evaluateJavaScript("window.__readerSelectionSpot()") { result, _ in
                guard let spot = result as? [Int], spot.count == 2 else { return }
                onPlaySelection(spot[0], spot[1])
            }
        }
        var onUserScroll: () -> Void = {}
        var onSpotSide: (JumpDirection) -> Void = { _ in }
        var onOpenLink: (URL) -> Void = { _ in }
        weak var chrome: ReadingChrome?
        weak var webView: WKWebView?
        var lastHTML: String = ""
        var lastHeading: ReaderHeading?
        var sizes = ReadingStyle.Sizes()
        private var sentSizes: ReadingStyle.Sizes?
        /// The colours, typeface, text size and spacing. Set before the first load by `makeUIView`,
        /// then through `setLook`.
        var look = ReadingStyle.Look.standard
        private var sentLook: ReadingStyle.Look?
        var animates = true
        /// Following the audio (Now Playing). Set before the first load by `makeUIView`.
        var follows = false
        /// Opens with the sentence in the middle (the Reader's saved spot). Set before the first
        /// load by `makeUIView`.
        var opensAtSentence = false
        private(set) var loaded = false
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
        private(set) var textInsets = ReaderTextInsets()
        private var sentInsets: ReaderTextInsets?
        /// Scroll or Pages (`setLayout`): it puts on screen what this coordinator decides to show.
        private(set) lazy var layout: ReadingTextLayout = ScrollTextLayout(host: self)

        /// Where the app keeps the text until the user moves it (a drag, a page turn, a link).
        enum Hold: Equatable {
            /// A fresh page: its top, the first line just below the top bar.
            case top
            /// Another page's place (D2), until the layout has put it on screen.
            case handOver(ReadingHandOver)
            /// The spoken sentence in the middle (the Reader's saved spot).
            case spoken
            /// A paragraph scrubbed to, until the layout has shown it.
            case paragraph(Int)
        }
        /// Nil: the reader's own place, which a new layout keeps on screen.
        private(set) var hold: Hold?

        init(onTapParagraph: @escaping (Int) -> Void) {
            self.onTapParagraph = onTapParagraph
        }

        /// Shows `html`. `opensAt` is where this load opens (the D2 handoff); any other load opens
        /// at the top, or at the spoken sentence when following or `opensAtSentence`.
        func load(html: String, heading: ReaderHeading? = nil, opensAt: ReadingHandOver? = nil) {
            lastHTML = html
            lastHeading = heading
            loaded = false
            sentActive = nil
            sentSentence = nil
            sentSizes = sizes
            sentLook = look
            loadGeneration += 1
            hold = opensAt.map(Hold.handOver) ?? (opensAtSentence ? .spoken : .top)
            spokenShown = nil
            textTop = 0
            reflowing = false
            queuedReflow = []
            layout.reset()
            webView?.loadHTMLString(Self.wrap(html, heading: heading, sizes: sizes, look: look), baseURL: nil)
        }

        /// Scroll ↔ Pages (`pages`: Pages mode's state, nil in Scroll mode), live: the line at the
        /// top of the reading area stays there. A load in flight opens in the new mode.
        func setLayout(pages model: ReadingPages?, footer: CGFloat) {
            if let pages = layout as? PagesTextLayout, pages.model === model { return pages.setFooter(footer) }
            guard model != nil || layout is PagesTextLayout else { return }
            layout.deactivate()
            if case .handOver = hold { hold = nil }
            webView?.scrollView.showsVerticalScrollIndicator = model == nil
            if let model {
                let pages = PagesTextLayout(host: self, model: model, footer: footer)
                layout = pages
                if loaded { pages.activate() }
            } else {
                layout = ScrollTextLayout(host: self)
                if loaded { reapplyInsets() }
            }
        }

        /// How far the article text starts below the top of the page's content (the title and
        /// source line); 0 with nothing above it. Measured on load.
        private(set) var textTop: CGFloat = 0

        /// The scroll position handed to another page (the Reader's, to Now Playing). At the top
        /// (the text's first line not yet scrolled above the top of the reading area) it is
        /// `.top`. Scrolled into the text, it is how far the top of the article text sits above
        /// the top of the window: that counts what is above the text on the page (the title) and where the web view sits on screen, so the
        /// page that opens at it shows the same line at the same place on screen. Nil while the web view is off screen.
        var handOver: ReadingHandOver? {
            guard let webView, webView.window != nil else { return nil }
            let sv = webView.scrollView
            // Half a point of slack: a page at its top can sit a fraction off it.
            guard sv.contentOffset.y + sv.contentInset.top > textTop + 0.5 else { return .top }
            return .text(offset: sv.contentOffset.y - textTop - viewportTop(of: webView))
        }

        /// The document y of the top of the reading area that opens at `handOver` (scrolled into
        /// the text).
        func documentY(of handOver: CGFloat, in webView: WKWebView) -> CGFloat {
            textTop + max(0, viewportTop(of: webView) + webView.scrollView.contentInset.top + handOver)
        }

        /// The window y of the top of the web view's scroll view (its viewport).
        func viewportTop(of webView: WKWebView) -> CGFloat {
            let sv = webView.scrollView
            return sv.convert(CGPoint(x: 0, y: sv.bounds.minY), to: nil).y
        }

        /// Measures `textTop` (after any style change queued before it), then runs `then`.
        private func measureTextTop(then: (() -> Void)? = nil) {
            guard let webView else { return }
            let generation = loadGeneration
            webView.evaluateJavaScript("window.__readerTextTop()") { [weak self] result, _ in
                guard let self, generation == self.loadGeneration else { return }
                self.textTop = CGFloat((result as? Double) ?? 0)
                then?()
            }
        }

        /// Asks the page where something sits (`js` answers [document top, height, the text's
        /// top]) and hands the top and height to `then`, for the load it was asked on.
        func locate(_ js: String, then: @escaping (_ top: CGFloat, _ height: CGFloat) -> Void) {
            guard let webView else { return }
            let generation = loadGeneration
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, generation == loadGeneration, let rect = result as? [Double], rect.count == 3 else { return }
                textTop = CGFloat(rect[2])
                then(CGFloat(rect[0]), CGFloat(rect[1]))
            }
        }

        /// Counts loads, so an answer from the page (and a layout's timers) only acts on the page
        /// it was asked about.
        private(set) var loadGeneration = 0

        // MARK: Putting the hold on screen

        /// The page opened, or laid out again (a reflow, Pages measured): the hold goes back on
        /// screen. A hand-over is the layout's to place; the spoken sentence goes to the middle
        /// while the text goes there.
        func placeHold() {
            spotRect = nil
            defer { updateSpotSide() }
            switch hold {
            case .handOver:
                break
            case .paragraph(let index):
                showParagraph(index)
            case .top, .spoken, nil:
                if goesToSpoken { goToSpoken(.jump, explicit: true) }
            }
        }

        /// The layout has put a hand-over on screen: the place is the reader's from now on.
        func handOverPlaced() {
            if case .handOver = hold { hold = nil }
        }

        /// The character a new pagination keeps on screen for the hold (the spoken sentence's
        /// first, or a scrubbed paragraph's); nil: the reader's own place.
        var heldSpot: ReadingPages.Spot? {
            switch hold {
            case .paragraph(let index): ReadingPages.Spot(paragraph: index, offset: 0)
            case .handOver: nil
            case .top, .spoken, nil: goesToSpoken ? spokenSpot.map(ReadingPages.Spot.init) : nil
            }
        }

        /// The paragraph scrubbed to, in the middle; the hold goes once the layout has shown it.
        private func showParagraph(_ index: Int) {
            if let pages = layout as? PagesTextLayout {
                hold = nil
                return pages.show(spot: ReadingPages.Spot(paragraph: index, offset: 0))
            }
            locate("window.__readerSpokenRect(\(index), null, null)") { [weak self] top, height in
                guard let self, hold == .paragraph(index) else { return }
                if layout.show(top: top, height: height, .centre(.jump)) { hold = nil }
            }
        }

        // MARK: Reflow (Dynamic Type) keeps the line being read

        private var reflowing = false
        private var queuedReflow: [String] = []

        /// Runs `change` (a style change that reflows the page) keeping the line being read: the
        /// reading anchor (the paragraph and the UTF-16 offset of the first character on the line
        /// at the top of the reading area, `layout.reflowAnchor()`), measured before and after the
        /// change in one go. The layout keeps it on screen, then the hold goes back. Changes run
        /// one at a time, so each anchor is measured on the page as the last one left it.
        private func reflow(_ change: String) {
            guard loaded, let webView else { return }
            guard !reflowing else { return queuedReflow.append(change) }
            reflowing = true
            let generation = loadGeneration
            let anchor = layout.reflowAnchor()
            let js = "(function(){ var a = window.__readerAnchor(\(Double(anchor.y))); \(change)"
                + " return window.__readerAnchorMoved(a); })();"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, generation == loadGeneration else { return }
                reflowing = false
                if let moved = result as? [Double], moved.count == 4 {
                    textTop = CGFloat(moved[3])
                    layout.reflowed(ReadingReflow(lineBefore: moved[0], lineAfter: moved[1],
                                                  textTopBefore: moved[2], textTopAfter: moved[3]), atTop: anchor.atTop)
                }
                if !queuedReflow.isEmpty {
                    let next = queuedReflow.joined(separator: " ")
                    queuedReflow = []
                    reflow(next)
                }
            }
        }

        /// Keeps the scroll view's top / bottom inset equal to the chrome over the text, so the
        /// first line starts below it and the last one scrolls clear of it.
        func setTextInsets(_ insets: ReaderTextInsets) {
            textInsets = insets
            guard insets != sentInsets, webView != nil else { return }
            sentInsets = insets
            layout.setInsets(insets)
        }

        /// The insets again, for a new layout or a new viewport.
        func reapplyInsets() {
            sentInsets = nil
            setTextInsets(textInsets)
        }

        func setSizes(_ sizes: ReadingStyle.Sizes) {
            self.sizes = sizes
            guard loaded, sizes != sentSizes else { return }
            sentSizes = sizes
            reflow(ReadingStyle.variablesScript(sizes, look))
        }

        /// A new reading appearance, live: colours alone repaint; a typeface, size or spacing
        /// change reflows the text, keeping the line on screen where it was.
        func setLook(_ look: ReadingStyle.Look) {
            let old = sentLook
            self.look = look
            guard loaded, look != old else { return }
            sentLook = look
            (layout as? PagesTextLayout)?.lookChanged()
            let script = ReadingStyle.variablesScript(sizes, look)
            if let old, old.font == look.font, old.lineSpacing == look.lineSpacing, old.textScale == look.textScale {
                webView?.evaluateJavaScript(script, completionHandler: nil)
            } else {
                reflow(script)
            }
        }

        /// Hands a pull at the top of the text to the sheet around it (`SheetPullHandoff`), and reports the finger.
        let pullHandoff = ScrollPullHandoff()

        /// Where the text's offset goes: the compact chrome's collapse (`ReadingChrome`). A finger's
        /// scroll (dragging or decelerating) decides it; any other move (following the audio, a
        /// scrub, a restore) only moves the point the next finger scroll is measured from.
        private var offsetObservation: NSKeyValueObservation?

        /// Notes a finger drag through the scroll view's pan (WebKit owns its delegate;
        /// programmatic scrolls never reach it): the user took over the text; a pull down at the top
        /// brings full screen's bars back (none in jump mode; regular width only); let go, the layout settles it (Pages
        /// snaps to a page). Following stops once the drag moves the text: a pull of the sheet alone
        /// (a pull down from the top) keeps following, as it moves nothing.
        func observeDragging(_ scrollView: UIScrollView) {
            pullHandoff.onDragBegan = { [weak self] in
                self?.userTookOver()
                self?.chrome?.textMoved(to: Self.scrolledIn(scrollView))
            }
            pullHandoff.onMove = { [weak self] delta in
                guard let self, !jumpMode, delta > 0, Self.scrolledIn(scrollView) <= 0 else { return }
                chrome?.pulledDownAtTop()
            }
            pullHandoff.onScroll = { [weak self] in self?.stopFollowing() }
            pullHandoff.onRelease = { [weak self] velocity in self?.layout.dragEnded(velocity: velocity) }
            pullHandoff.attach(to: scrollView)
            offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                let byFinger = scrollView.isDragging || scrollView.isDecelerating
                let farthest = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                    + scrollView.adjustedContentInset.top - scrollView.bounds.height
                let offset = min(Self.scrolledIn(scrollView), max(farthest, 0))
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.updateSpotSide()
                    guard !self.jumpMode else { return }
                    if byFinger { self.chrome?.userScrolled(to: offset) } else { self.chrome?.textMoved(to: offset) }
                }
            }
        }

        /// How far the text is scrolled from its top (below the header's inset); negative while a
        /// pull stretches it.
        private static func scrolledIn(_ scrollView: UIScrollView) -> CGFloat {
            scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        }

        /// The user moved the text (a drag, a page turn, a link): the hold goes.
        func userTookOver() {
            hold = nil
            layout.cancelSettling()
        }

        /// The user moved the text while it followed the audio: it stops (Jump to Audio resumes).
        func stopFollowing() {
            guard follows else { return }
            follows = false
            updateSpotSide()
            onUserScroll()
        }

        // MARK: Which way the spoken sentence is

        /// The spoken sentence's place in the document, as the page last said (`args` is the call's
        /// arguments, which name the sentence): the scroll layout's compare against the visible text.
        private var spotRect: (args: String, top: CGFloat, height: CGFloat)?
        private var spotRectAsked: String?
        private var lastSide: JumpDirection?

        private func spotArgs(_ spot: (paragraph: Int, sentence: ReaderSentence?)) -> String {
            spot.sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "\(spot.paragraph), null, null"
        }

        /// While the text isn't following the audio, tells the owner which way the spoken sentence is
        /// (Jump to Audio's arrow). Scroll: its middle against the middle of the visible text, between
        /// the insets (the page's answer is kept, so a drag costs no calls); Pages: its page against
        /// the one shown. Only a change is reported.
        func updateSpotSide() {
            guard loaded, !follows, let spot = spokenSpot, let webView else { return }
            if let pages = layout as? PagesTextLayout {
                if let side = pages.side(of: ReadingPages.Spot(spot)) { report(side) }
                return
            }
            let args = spotArgs(spot)
            guard let rect = spotRect, rect.args == args else {
                guard spotRectAsked != args else { return }
                spotRectAsked = args
                locate("window.__readerSpokenRect(\(args))") { [weak self] top, height in
                    guard let self else { return }
                    spotRectAsked = nil
                    spotRect = (args, top, height)
                    updateSpotSide()
                }
                return
            }
            let sv = webView.scrollView
            let visibleTop = sv.contentOffset.y + sv.adjustedContentInset.top
            let visibleBottom = sv.contentOffset.y + sv.bounds.height - sv.adjustedContentInset.bottom
            report(rect.top + rect.height / 2 < (visibleTop + visibleBottom) / 2 ? .up : .down)
        }

        private func report(_ side: JumpDirection) {
            guard side != lastSide else { return }
            lastSide = side
            onSpotSide(side)
        }

        /// Scrub-follow: the paragraph under the scrub thumb, in the middle.
        func scroll(_ request: ReaderScrollRequest?) {
            guard let request, request.token != lastScrollToken, webView != nil else { return }
            lastScrollToken = request.token
            layout.cancelSettling()
            hold = .paragraph(request.index)
            if loaded { showParagraph(request.index) }
        }

        /// Following turned on (Jump to Audio, or another page started): go to the spoken sentence.
        func setFollows(_ on: Bool) {
            guard on != follows else { return }
            follows = on
            if on { goToSpoken(.animate, explicit: true) }
        }

        // MARK: Going to the spoken sentence

        /// How the text goes to the spoken sentence.
        enum SpokenMove {
            /// At once, held there while the layout settles (opening, a reflow, Reduce Motion).
            case jump
            /// On the `Motion.standard` spring (Jump to Audio, a new paragraph).
            case animate
            /// On the spring, only when the sentence isn't wholly in the visible text: a long
            /// paragraph's sentences reaching its edge.
            case intoView
        }

        /// Where the text last went for the audio: the paragraph, and whether its sentence was
        /// known then (a sentence that comes later is gone to when it does).
        private var spokenShown: (paragraph: Int, hadSentence: Bool)?
        /// Counts requests to go to the sentence: only the newest one's answer moves the text.
        private var spokenRequest = 0

        /// The text goes to the spoken sentence: while following, or opened at the sentence and
        /// not moved since.
        var goesToSpoken: Bool { follows || hold == .spoken }

        /// Where that is: the sentence when it is in the spoken paragraph (or the sentence alone,
        /// with no paragraph spoken), else the spoken paragraph.
        var spokenSpot: (paragraph: Int, sentence: ReaderSentence?)? {
            guard let paragraph = pendingActive ?? pendingSentence?.paragraph else { return nil }
            return (paragraph, pendingSentence?.paragraph == paragraph ? pendingSentence : nil)
        }

        /// Shows the spoken sentence (else the spoken paragraph): in the middle of the visible
        /// text, or its page. A long paragraph's middle can be screens away from the sentence
        /// being read, so the sentence, not the paragraph, is what is shown. Going there drops a
        /// hand-over still being placed (following takes over at the next paragraph).
        /// Pages never follow the audio (C108): only an explicit move (opening at the sentence, a
        /// new layout keeping it, *Jump to Audio*) shows the spoken sentence's page.
        func goToSpoken(_ move: SpokenMove, explicit: Bool = false) {
            guard loaded, goesToSpoken, let spot = spokenSpot else { return }
            if let pages = layout as? PagesTextLayout {
                guard explicit else { return }
                handOverPlaced()
                return pages.show(spot: ReadingPages.Spot(spot))
            }
            if move != .intoView {
                layout.cancelSettling()
                handOverPlaced()
            }
            spokenShown = (spot.paragraph, spot.sentence != nil)
            spokenRequest += 1
            let request = spokenRequest
            let args = spot.sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "\(spot.paragraph), null, null"
            locate("window.__readerSpokenRect(\(args))") { [weak self] top, height in
                self?.spotRect = (args, top, height)
                // While the sheet is pulled the text is held at its top; the next sentence goes.
                guard let self, request == spokenRequest, goesToSpoken, !pullHandoff.isPulling else { return }
                layout.show(top: top, height: height, .centre(move))
            }
        }

        func setActiveParagraph(_ index: Int?) {
            let changed = pendingActive != index
            pendingActive = index
            if changed { spotRect = nil }
            defer { updateSpotSide() }
            guard sentActive != .some(index), let webView, loaded else { return }
            sentActive = .some(index)
            let arg = index.map(String.init) ?? "null"
            webView.evaluateJavaScript(
                "window.__readerSetActive && window.__readerSetActive(\(arg));",
                completionHandler: nil
            )
            if changed, follows, let index {
                if layout is PagesTextLayout { return layout.follow(word: ReadingPages.Spot(paragraph: index, offset: 0)) }
                goToSpoken(.animate)
            }
        }

        func setSentence(_ sentence: ReaderSentence?) {
            if pendingSentence != sentence { spotRect = nil }
            pendingSentence = sentence
            defer { updateSpotSide() }
            guard sentSentence != .some(sentence), let webView, loaded else { return }
            sentSentence = .some(sentence)
            let args = sentence.map { "\($0.paragraph), \($0.start), \($0.end)" } ?? "null"
            webView.evaluateJavaScript("window.__readerSetSentence && window.__readerSetSentence(\(args));",
                                       completionHandler: nil)
            guard let sentence else { return }
            // Opened at the sentence, which came after the page: it goes there now.
            if !follows, hold == .spoken { return goToSpoken(.jump, explicit: true) }
            if layout is PagesTextLayout { return }
            // Following, within the paragraph the text last went to: to its sentence when the text
            // went there before the sentence was known, else only to keep the sentence in view.
            guard follows, sentence.paragraph == pendingActive, let shown = spokenShown,
                  shown.paragraph == sentence.paragraph else { return }
            goToSpoken(shown.hadSentence ? .intoView : .animate)
        }

        /// The word being spoken (`HTMLReadingView.spokenWord`).
        private(set) var spokenWord: ReadingPages.Spot?

        /// Following, the layout keeps the spoken word on screen as it moves (Pages turns to the
        /// next page when it gets there; Scroll moves by the sentence).
        func setSpokenWord(_ word: ReadingPages.Spot?) {
            guard word != spokenWord else { return }
            spokenWord = word
            if loaded, follows, !pullHandoff.isPulling, let word { layout.follow(word: word) }
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
            guard message.name == "readerBridge", let body = message.body as? [String: Any] else { return }
            if let x = body["tapX"] as? Double, let width = body["width"] as? Double {
                textTapped(x: CGFloat(x), width: CGFloat(width))
            } else if body["layout"] != nil {
                if loaded { layout.contentChanged() }
            } else if jumpMode, let index = body["index"] as? Int {
                DispatchQueue.main.async { self.onTapParagraph(index) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            // Sizes that changed while the page loaded: a fresh page, nothing to keep in place
            // yet. First, so the page is measured as it will be.
            sentSizes = sizes
            sentLook = look
            webView.evaluateJavaScript(ReadingStyle.variablesScript(sizes, look), completionHandler: nil)
            reapplyInsets()
            sentActive = nil
            setActiveParagraph(pendingActive)
            sentSentence = nil
            setSentence(pendingSentence)
            lastSentJumpMode = nil
            setJumpMode(jumpMode)
            layout.opened()
            guard case .handOver(let handOver) = hold else {
                measureTextTop()
                return placeHold()
            }
            // Handed over from the Reader: its top, or the same line at the same place on screen
            // (see `handOver`). A drag or scrub meanwhile drops it.
            measureTextTop { [weak self] in
                guard let self, hold == .handOver(handOver) else { return }
                layout.open(handOver: handOver)
            }
        }
    }
}
