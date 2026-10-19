import UIKit
import WebKit

/// Scroll mode: the text is one column that scrolls.
///
/// - The spoken sentence goes to the middle of the visible text: between the bars, or the whole
///   screen while they are hidden (the bars coming back over it never move it). Moves run on the
///   `Motion.standard` spring (a jump under Reduce Motion).
/// - An offset the page can't hold yet (a hand-over, a jump while the page lays out) is settled:
///   worked out again on every frame until layout has been still a moment (`ReadingScrollRestore`).
/// - A reflow keeps the line at the top of the reading area where it is on screen; a page at its
///   top stays at its top.
/// - An edge tap turns a screen: the visible text less one line, so the line at one edge stays in
///   view at the other, landing with a whole line at the top. In full screen the visible text
///   starts below the fade at the top (`HTMLReadingView`).
/// - In full screen a drag let go comes to rest the same way: where its glide would stop, moved to
///   the nearest line, so no line rests cut by the screen's top edge.
@MainActor
final class ScrollTextLayout: ReadingTextLayout {
    private unowned let host: HTMLReadingWebView.Coordinator

    init(host: HTMLReadingWebView.Coordinator) {
        self.host = host
    }

    private var scrollView: UIScrollView? { host.webView?.scrollView }

    func reset() {
        cancelSettling()
    }

    func opened() {
        // A fresh page starts at the top, just below the top chrome; a drag while it loaded keeps
        // the text where it is.
        guard host.hold != nil else { return }
        showTop()
    }

    func open(handOver: ReadingHandOver) {
        settle(at: .handOver(handOver))
    }

    func show(top: CGFloat, height: CGFloat, _ placement: ReadingPlacement) -> Bool {
        guard let sv = scrollView else { return false }
        switch placement {
        case .centre(let move):
            centre(top: top, height: height, move, in: sv)
        case .top:
            scroll(to: sv.readingLayout.clamped(top - sv.contentInset.top))
        }
        return true
    }

    func dragEnded(velocity: CGFloat) {
        guard host.chrome?.hidden == true, let sv = scrollView, let webView = host.webView, host.loaded else { return }
        let layout = sv.readingLayout
        guard layout.isLaidOut else { return }
        // Where UIKit's glide would stop (its normal deceleration), as the line to settle on.
        let rate = UIScrollView.DecelerationRate.normal.rawValue
        let glide = velocity / 1000 * rate / (1 - rate)
        let projected = layout.clamped(sv.contentOffset.y - glide)
        // At either end of the text the page rests as it is.
        guard projected > layout.range.lowerBound + 1, projected < layout.range.upperBound - 1 else { return }
        let line = host.look.lineHeight(host.sizes)
        let generation = host.loadGeneration
        webView.evaluateJavaScript("window.__readerAnchor(\(Double(projected + line)))") { [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self, !sv.isTracking else { return }
            guard let lineTop = ((result as? [String: Any])?["top"] as? Double).map({ CGFloat($0) }),
                  abs(lineTop - (projected + line)) <= line else { return }
            // The line under the fade's foot comes to rest there, whole; the glide stops for it.
            sv.setContentOffset(sv.contentOffset, animated: false)
            scroll(to: sv.readingLayout.clamped(lineTop - line))
        }
    }

    func turn(forward: Bool) -> Bool {
        guard let sv = scrollView, let webView = host.webView, host.loaded else { return false }
        let line = host.look.lineHeight(host.sizes)
        // Where the visible text starts: below the top bar, or in full screen below the top's
        // fade (`HTMLReadingView`).
        let fullScreen = host.chrome?.hidden == true
        let top = fullScreen ? line : sv.contentInset.top
        let visible = sv.bounds.height - top - (fullScreen ? 0 : sv.contentInset.bottom)
        let step = max(visible - line, line)
        let layout = sv.readingLayout
        guard layout.isLaidOut else { return false }
        let rough = layout.clamped(sv.contentOffset.y + (forward ? step : -step))
        guard abs(rough - sv.contentOffset.y) > 0.5 else { return false }
        // A whole line at the top: forward, the line the rough top cuts (the one cut at the foot
        // before, shown whole); back, the first line wholly below it (so the old top line stays
        // whole at the foot). Away from text (a picture), the rough step.
        let generation = host.loadGeneration
        let y = rough + top + (forward ? 0 : line - 1)
        webView.evaluateJavaScript("window.__readerAnchor(\(Double(y)))") { [weak self] result, _ in
            guard let self, generation == host.loadGeneration, host.layout === self else { return }
            let lineTop = ((result as? [String: Any])?["top"] as? Double).map { CGFloat($0) }
            let aligned = lineTop.flatMap { abs($0 - (rough + top)) <= line ? $0 - top : nil } ?? rough
            scroll(to: sv.readingLayout.clamped(aligned))
        }
        return true
    }

    /// Keeps the first line below the top chrome (a fresh page), or the saved spot in the middle
    /// of the new visible text; following, the next sentence places the text.
    func setInsets(_ insets: ReaderTextInsets) {
        guard let sv = scrollView else { return }
        let wasAtTop = host.hold == .top || sv.contentOffset.y <= -sv.contentInset.top + 2
        let inset = UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
        sv.contentInset = inset
        sv.verticalScrollIndicatorInsets = inset
        guard !sv.isTracking, !host.follows else { return }
        switch host.hold {
        case .handOver?:
            break
        case .spoken? where host.spokenSpot != nil:
            host.goToSpoken(.jump)
        default:
            if wasAtTop, settling == nil { showTop() }
        }
    }

    func reflowAnchor() -> (y: CGFloat, atTop: Bool) {
        guard let webView = host.webView else { return (0, true) }
        let sv = webView.scrollView
        let atTop = sv.contentOffset.y <= -sv.contentInset.top + 1
        // A hand-over still settling: where the top of the reading area will be.
        if case .handOver(.text(let offset))? = settling?.target {
            return (host.documentY(of: offset, in: webView), atTop)
        }
        return (sv.contentOffset.y + sv.contentInset.top, atTop)
    }

    func reflowed(_ reflow: ReadingReflow, atTop: Bool) {
        guard let sv = scrollView else { return }
        if let target = settling?.target {
            // Still settling: the target follows the line through the text (a change above the
            // text alone moves `textTop`, which the next frame reads).
            switch target {
            case .handOver(.text(let offset)): settling?.target = .handOver(.text(offset: offset + reflow.movedInText))
            case .text(let offset): settling?.target = .text(offset: offset + reflow.movedInText)
            case .handOver(.top): break
            }
        } else if atTop {
            showTop()
        } else {
            sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: sv.contentOffset.y + reflow.moved)
        }
        host.placeHold()
    }

    func deactivate() {
        cancelSettling()
    }

    private func showTop() {
        guard let sv = scrollView else { return }
        sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: -sv.contentInset.top)
    }

    /// Scrolls the spoken sentence, `height` tall at document y `top`, to the middle of the
    /// visible text: between the bars, or the whole screen while they are hidden.
    private func centre(top: CGFloat, height: CGFloat, _ move: HTMLReadingWebView.Coordinator.SpokenMove,
                        in sv: UIScrollView) {
        // Full screen: from the screen's top edge (the strip above the sheet shows the page's
        // colour) to its foot.
        let fullScreen = host.chrome?.hidden == true
        let insetTop = fullScreen ? -sv.convert(CGPoint(x: 0, y: sv.bounds.minY), to: nil).y : sv.contentInset.top
        let visibleTop = sv.contentOffset.y + insetTop
        let visible = sv.bounds.height - insetTop - (fullScreen ? 0 : sv.contentInset.bottom)
        if move == .intoView {
            // Opening still holds the page; a sentence in view stays where it is.
            guard settling == nil, top < visibleTop || top + height > visibleTop + visible else { return }
        }
        let y = top + height / 2 - insetTop - visible / 2
        let layout = sv.readingLayout
        // Before the scroll view holds the page's layout an offset doesn't stick: it settles.
        guard move != .jump, host.animates, layout.isLaidOut else { return settle(at: .text(offset: y - host.textTop)) }
        let target = layout.clamped(y)
        guard abs(target - sv.contentOffset.y) > 1 else { return }
        scroll(to: target)
    }

    /// Scrolls to offset `y` on the `Motion.standard` spring (at once under Reduce Motion).
    private func scroll(to y: CGFloat) {
        guard let sv = scrollView else { return }
        let offset = CGPoint(x: sv.contentOffset.x, y: y)
        guard host.animates else { return sv.contentOffset = offset }
        UIView.animate(springDuration: Motion.standardResponse, bounce: Motion.standardBounce,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            sv.contentOffset = offset
        }
    }

    // MARK: Settling an offset while the page lays out

    /// What a settling offset is.
    private enum Target: Equatable {
        /// Another page's position (D2).
        case handOver(ReadingHandOver)
        /// `offset` points below the text's top (so it moves with the text, not with the web view
        /// on screen).
        case text(offset: CGFloat)
    }

    /// The offset being put on screen: worked out again on every frame (`settleFrame`) until
    /// layout has been still for `timing.quiet`.
    private var settling: (target: Target, generation: Int, started: CFTimeInterval)?
    private var link: CADisplayLink?
    /// The last frame's target and layout, and when they last changed.
    private var seen: (target: CGFloat, layout: ReadingScrollRestore.Layout)?
    private var seenChanged: CFTimeInterval = 0
    /// How long the target and layout must stay still before settling ends (and an offset the
    /// page can't reach is clamped), and the longest it lasts at all, in seconds.
    private let timing = (quiet: 0.3, limit: 2.0)

    var isSettling: Bool { settling != nil }

    /// Puts the text at `target` once the page's layout can hold it, and keeps it there while the
    /// layout settles: the title card measured, the header growing, what is above the text
    /// changing size (see `ReadingScrollRestore`).
    private func settle(at target: Target) {
        let now = CACurrentMediaTime()
        settling = (target, host.loadGeneration, now)
        seen = nil
        seenChanged = now
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(settleFrame))
        link.add(to: .main, forMode: .common)
        self.link = link
        settleFrame()
    }

    @objc private func settleFrame() {
        guard let settling, settling.generation == host.loadGeneration, let webView = host.webView else {
            return cancelSettling()
        }
        let sv = webView.scrollView
        let target = switch settling.target {
        case .handOver(.top): -sv.contentInset.top
        case .handOver(.text(let offset)): offset + host.textTop + host.viewportTop(of: webView)
        case .text(let offset): offset + host.textTop
        }
        let layout = sv.readingLayout
        let now = CACurrentMediaTime()
        if seen.map({ abs($0.target - target) > 0.01 || $0.layout != layout }) ?? true {
            seen = (target, layout)
            seenChanged = now
        }
        let quiet = now - seenChanged >= timing.quiet
        let expired = now - settling.started >= timing.limit
        let step = ReadingScrollRestore(offset: target, generation: settling.generation)
            .step(in: layout, quiet: quiet, expired: expired)
        guard case .scroll(let y) = step else { return }
        if abs(sv.contentOffset.y - y) > 0.01 { sv.contentOffset = CGPoint(x: sv.contentOffset.x, y: y) }
        guard quiet || expired else { return }
        cancelSettling()
        host.handOverPlaced()
    }

    /// A newer move (a drag, a scrub, a follow) or another load wins.
    func cancelSettling() {
        settling = nil
        link?.invalidate()
        link = nil
    }
}

extension UIScrollView {
    /// What `ReadingScrollRestore` needs of this scroll view's layout.
    var readingLayout: ReadingScrollRestore.Layout {
        ReadingScrollRestore.Layout(contentHeight: contentSize.height, viewportHeight: bounds.height,
                                    insetTop: contentInset.top, insetBottom: contentInset.bottom)
    }
}
