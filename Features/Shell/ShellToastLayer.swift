import SwiftUI

/// The shell's toast (`ShellState.toast`), floating just above the bottom chrome it is attached
/// to (`.overlay(alignment: .top)` on a band): the browser's, the Library's, the Favorites
/// sheet's, the Reader's and Now Playing's (their `floating` slot). The Move tree and the import
/// sheet have none, so their toast floats a toolbar row above the sheet's bottom
/// (`sheetToastLayer()`). It goes by itself after `Toast.duration` (longer when it has an
/// action); a layer that disappears meanwhile doesn't take it with it (`ShellState.expireToast`).
struct ShellToastLayer: View {
    @Environment(ShellState.self) private var shell

    /// A line with no height at the chrome's top edge; the toast hangs above it, its bottom a gap
    /// over the chrome (over the Now Playing bar's top, never on it). The overlay offers the toast
    /// that zero height, which would cut its message to one line: it takes its own height.
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .overlay(alignment: .bottom) { toast }
    }

    @ViewBuilder
    private var toast: some View {
        if let toast = shell.toast {
            Toast(message: toast.message, systemImage: toast.systemImage, actionTitle: toast.actionTitle) {
                shell.dismissToast(toast.id)
                toast.action?()
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.bottom, Spacing.xs)
            .transition(.opacity)
            .task(id: toast.id) {
                await shell.expireToast(toast.id, after: toast.actionTitle == nil ? Toast.duration : Toast.actionDuration)
            }
        }
    }
}

extension View {
    /// The shell's toast over a sheet with no bottom chrome (the Move tree, the import sheet). What
    /// shows of a medium-detent sheet ends above its content's bottom, where the sheet's rounded
    /// edge would cut a toast anchored there: it floats a toolbar row up, where it would sit over
    /// chrome.
    func sheetToastLayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 0).overlay(alignment: .top) {
                ShellToastLayer().offset(y: -BottomChrome.rowHeight)
            }
        }
    }
}
