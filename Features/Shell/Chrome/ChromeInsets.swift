import SwiftUI
import UIKit

/// The home indicator's strip on this phone (the window's bottom safe area, the keyboard's left
/// out; 0 with a Home button): the chrome's rows end on it, and what the chrome covers is measured
/// from it (`clearance(step:)`), or from the screen's edge with it added (`footprint(step:)`).
/// The root view reports it (`reportsChromeHome()`); reading the window's insets in a view's body
/// instead makes SwiftUI's graph loop and remount the page's web view.
@MainActor
@Observable
final class ChromeHome {
    static let shared = ChromeHome()
    private(set) var value: CGFloat = ChromeMetrics.homeIndicatorStrip

    static var inset: CGFloat { shared.value }

    /// What the chrome covers above this phone's safe area at a fold step (`ChromeMetrics.clearance`).
    static func clearance(step: Int) -> CGFloat { ChromeMetrics.clearance(step: step, home: inset) }
    /// The same from the screen's edge, for a view laid out through the strip.
    static func footprint(step: Int) -> CGFloat { clearance(step: step) + inset }

    fileprivate func report(_ bottom: CGFloat) { if value != bottom { value = bottom } }
}

extension View {
    /// Reports the window's bottom safe area (without the keyboard) to `ChromeHome`. On the root view.
    /// A geometry proxy's inset includes the keyboard's, so the change only triggers the read: the value
    /// is the window's own, read outside the body.
    func reportsChromeHome() -> some View {
        onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { _ in
            let window = UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
            if let window { ChromeHome.shared.report(window.safeAreaInsets.bottom) }
        }
    }
}

/// Where a screen's scroll position goes: the chrome folds a step at a time as it scrolls down (a tap on
/// the bubble opens it).
extension View {
    /// Reports this view's scroll views' offset to `chrome` as `source`, past the rubber band at both ends.
    func chromeScrollSource(_ chrome: ChromeScroll, as source: ChromeSource) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            let top = geometry.contentInsets.top
            let farthest = geometry.contentSize.height + geometry.contentInsets.bottom + top - geometry.containerSize.height
            return min(geometry.contentOffset.y + top, max(farthest, 0))
        } action: { _, offset in
            chrome.scrolled(to: offset, from: source)
        }
    }
}

/// A compact screen under the floating chrome: scrolls through the bottom safe area and keeps its
/// last row clear of the chrome.
struct CompactChromeInsets: ViewModifier {
    let isCompact: Bool

    func body(content: Content) -> some View {
        if isCompact {
            content
                .contentMargins(.bottom, ChromeHome.clearance(step: 0), for: .scrollContent)
                .contentMargins(.bottom, ChromeHome.clearance(step: 0), for: .scrollIndicators)
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            content
        }
    }
}

/// Reports a screen's own scroll views to the chrome: a pushed screen has to do it itself, since
/// a modifier above the navigation stack doesn't reach inside it. The shell hands the chrome to the
/// new screen as its path changes (`ShellState.chromeOwner`).
struct CompactChromeScroll: ViewModifier {
    let isCompact: Bool
    let source: ChromeSource
    @Environment(ShellState.self) private var shell

    func body(content: Content) -> some View {
        if isCompact {
            content
                .chromeScrollSource(shell.chromeScroll, as: source)
        } else {
            content
        }
    }
}
