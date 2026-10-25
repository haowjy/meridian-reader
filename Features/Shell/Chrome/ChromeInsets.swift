import SwiftUI

/// Where a screen's scroll position goes: the chrome collapses as it scrolls down and opens as it
/// scrolls back.
extension View {
    /// Reports this view's scroll views' offset to `chrome`, past the rubber band at both ends.
    func chromeScrollSource(_ chrome: ChromeState) -> some View {
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
    @Environment(ShellState.self) private var shell

    func body(content: Content) -> some View {
        if isCompact {
            content
                .contentMargins(.bottom, ChromeMetrics.footprint, for: .scrollContent)
                .contentMargins(.bottom, ChromeMetrics.footprint, for: .scrollIndicators)
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
                .chromeScrollSource(shell.chrome)
                .onAppear { shell.chrome.reset() }
        } else {
            content
        }
    }
}
