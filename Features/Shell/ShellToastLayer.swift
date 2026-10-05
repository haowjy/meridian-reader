import SwiftUI

/// The shell's toast (`ShellState.toast`), floating just above the bottom chrome it is attached
/// to (`.overlay(alignment: .top)` on a band): the browser's, the Library's, the Favorites
/// sheet's, the Reader's, Now Playing's controls; the Move tree has none, so its toast floats a
/// toolbar row above the sheet's bottom. It goes by itself after `Toast.duration` (longer when it has an
/// action).
struct ShellToastLayer: View {
    @Environment(ShellState.self) private var shell

    var body: some View {
        if let toast = shell.toast {
            Toast(message: toast.message, systemImage: toast.systemImage, actionTitle: toast.actionTitle) {
                shell.dismissToast(toast.id)
                toast.action?()
            }
            .padding(.horizontal, Spacing.pageMargin)
            // Its bottom edge a gap above the chrome's top.
            .alignmentGuide(.top) { $0[.bottom] + Spacing.xs }
            .transition(.opacity)
            .task(id: toast.id) {
                try? await Task.sleep(for: toast.actionTitle == nil ? Toast.duration : Toast.actionDuration)
                withAnimation(Motion.snappy) { shell.dismissToast(toast.id) }
            }
        }
    }
}
