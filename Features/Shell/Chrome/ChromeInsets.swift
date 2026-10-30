import SwiftUI
import UIKit

/// The home indicator's strip on this phone (the window's bottom safe area, the keyboard's left
/// out; 0 with a Home button): the chrome's footprints are measured from the screen's edge, and
/// what is laid out above the safe area keeps clear of `ChromeMetrics.aboveSafeArea(_:home:)`.
/// The root view reports it (`reportsChromeHome()`); reading the window's insets in a view's body
/// instead makes SwiftUI's graph loop and remount the page's web view.
@MainActor
@Observable
final class ChromeHome {
    static let shared = ChromeHome()
    private(set) var value: CGFloat = ChromeMetrics.homeIndicatorStrip

    static var inset: CGFloat { shared.value }

    /// `footprint` (from the screen's edge) above this phone's safe area.
    static func above(_ footprint: CGFloat) -> CGFloat { ChromeMetrics.aboveSafeArea(footprint, home: inset) }

    fileprivate func report(_ bottom: CGFloat) { if value != bottom { value = bottom } }
}

extension View {
    /// Reports the window's bottom safe area (without the keyboard) to `ChromeHome`. On the root view.
    func reportsChromeHome() -> some View {
        background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { ChromeHome.shared.report($0) }
        }
    }
}

/// Where a screen's scroll position goes: the chrome folds a step at a time as it scrolls down (a tap on
/// the strip opens it).
extension View {
    /// Reports this view's scroll views' offset to `chrome`, past the rubber band at both ends.
    func chromeScrollSource(_ chrome: ChromeScroll) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            let top = geometry.contentInsets.top
            let farthest = geometry.contentSize.height + geometry.contentInsets.bottom + top - geometry.containerSize.height
            return min(geometry.contentOffset.y + top, max(farthest, 0))
        } action: { _, offset in
            chrome.scrolled(to: offset)
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
                .contentMargins(.bottom, ChromeHome.above(ChromeMetrics.footprint), for: .scrollContent)
                .contentMargins(.bottom, ChromeHome.above(ChromeMetrics.footprint), for: .scrollIndicators)
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            content
        }
    }
}

/// Reports a screen's own scroll views to the chrome: a pushed screen has to do it itself, since
/// a modifier above the navigation stack doesn't reach inside it.
struct CompactChromeScroll: ViewModifier {
    let isCompact: Bool
    @Environment(ShellState.self) private var shell

    func body(content: Content) -> some View {
        if isCompact {
            content
                .chromeScrollSource(shell.chromeScroll)
                .onAppear { shell.chromeScroll.reset() }
        } else {
            content
        }
    }
}
