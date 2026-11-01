#if DEBUG
import OSLog
import UIKit

/// One step of `-readerProbe`: a controller and rendering probe of the in-place reader's full screen,
/// not a gesture test (`isDragging` and `isDecelerating` stay false, so the finger-held inset branch,
/// the fling and the clamp rule are a real finger's to check).
enum ReaderProbeStep: Equatable {
    /// A gesture starts, as a drag's start does: the user takes over the text (no hold re-places it)
    /// and one move report at the current offset.
    case anchor
    /// The offset moves by N pt (down positive) as one finger report.
    case by(CGFloat)
    /// The offset goes to -N (a pull past the top) as one finger report.
    case pull(CGFloat)
    /// A rebound to N: a finger report per 20 pt, as UIKit's spring sends them.
    case rebound(CGFloat)
    /// The centre tap.
    case centre

    /// `a`, `dN`, `uN`, `pN`, `rN`, `c`, comma separated: `"a,d80,u30"`. Nil when any step doesn't parse.
    static func parse(_ text: String) -> [ReaderProbeStep]? {
        let steps = text.split(separator: ",").map { token -> ReaderProbeStep? in
            let kind = token.first
            let n = Double(token.dropFirst()).map { CGFloat($0) }
            switch (kind, n) {
            case ("a", nil): return .anchor
            case ("c", nil): return .centre
            case ("d", let n?): return .by(n)
            case ("u", let n?): return .by(-n)
            case ("p", let n?): return .pull(n)
            case ("r", let n?): return .rebound(n)
            default: return nil
            }
        }
        return steps.contains(nil) ? nil : steps.compactMap { $0 }
    }
}

extension HTMLReadingWebView.Coordinator {
    /// `-readerProbe`: the steps the first reading page shown runs once it has loaded and laid out.
    /// Set by the launch (`AppMain`).
    static var probeSteps: [ReaderProbeStep]?

    private static let probeLog = Logger(subsystem: "com.jimmyyao.Reader", category: "ReaderProbe")

    func runProbeIfAsked() {
        guard let steps = Self.probeSteps else { return }
        Self.probeSteps = nil
        let generation = loadGeneration
        Task { @MainActor [weak self] in
            // Laid out: the scroll view holds the page's height.
            for _ in 0..<100 {
                guard let self, generation == loadGeneration else { return }
                if let sv = webView?.scrollView, sv.readingLayout.isLaidOut, !layout.isSettling { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(1))
            Self.probeLog.notice("ReaderProbe start steps=\(steps.count, privacy: .public)")
            for (index, step) in steps.enumerated() {
                guard let self, generation == loadGeneration, let sv = webView?.scrollView else { return }
                run(step, in: sv)
                await settled()
                let y = sv.contentOffset.y + sv.adjustedContentInset.top
                Self.probeLog.notice("ReaderProbe step=\(index, privacy: .public):\(String(describing: step), privacy: .public) fullScreen=\(self.chrome?.hidden == true, privacy: .public) offset=\(Int(y.rounded()), privacy: .public) insetTop=\(Int(sv.adjustedContentInset.top), privacy: .public) insetBottom=\(Int(sv.adjustedContentInset.bottom), privacy: .public)")
                try? await Task.sleep(for: .seconds(1))
            }
            Self.probeLog.notice("ReaderProbe done")
        }
    }

    private func run(_ step: ReaderProbeStep, in sv: UIScrollView) {
        let top = sv.adjustedContentInset.top
        switch step {
        case .anchor:
            userTookOver()
            report(sv, byFinger: false)
        case .by(let n):
            probeMove(sv, to: sv.contentOffset.y + top + n)
        case .pull(let n):
            probeMove(sv, to: -n)
        case .rebound(let n):
            var y = sv.contentOffset.y + top
            while abs(y - n) > 0.5 {
                y += max(-20, min(20, n - y))
                probeMove(sv, to: y)
            }
        case .centre:
            chrome?.tappedCentre()
        }
    }

    /// Writes the offset (`scrolled` from the text's top) with the KVO report silenced, then sends
    /// exactly one finger report.
    private func probeMove(_ sv: UIScrollView, to scrolled: CGFloat) {
        probeSilences = true
        sv.contentOffset.y = scrolled - sv.adjustedContentInset.top
        probeSilences = false
        report(sv, byFinger: true)
    }

    /// Until `hidden` has held for one `Motion.standard` response: the step's effect is drawn.
    private func settled() async {
        var seen = chrome?.hidden
        var since = ContinuousClock.now
        let still = Duration.milliseconds(Int(Motion.standardResponse * 1000))
        while ContinuousClock.now - since < still {
            try? await Task.sleep(for: .milliseconds(50))
            if chrome?.hidden != seen {
                seen = chrome?.hidden
                since = .now
            }
        }
    }
}
#endif
