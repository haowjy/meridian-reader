import SwiftUI
import UIKit

/// The regular-width address / search band: the field, with a round ✕ beside it that ends the
/// session while searching (Safari-style). Lowering the keyboard keeps the session
/// (`lowersKeyboardOnPullDown`). The band owns the field's focus and keeps it in sync with
/// `session.isFocused`. Compact width draws its chrome in `ChromeHost`.
struct SurfaceBand<Field: View>: View {
    let session: SearchSession
    let cancelID: String
    let onCancel: () -> Void
    /// Starts the session when the idle field is tapped (the surface's own start: the browser's
    /// with the page address, the Library's with the screen it searches).
    let begin: () -> Void
    @ViewBuilder var field: (FocusState<Bool>.Binding) -> Field

    /// The field's focus, kept in sync with `session.isFocused`; `field` attaches it to its
    /// `TextField`.
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            field($focused)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("bandField")
            if session.isActive {
                Button(action: onCancel) {
                    Image(systemName: Icons.close)
                        .foregroundStyle(Palette.ink)
                        .roundFieldControl(fill: Palette.chrome)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Verbs.cancel)
                .accessibilityIdentifier(cancelID)
            }
        }
        .bottomChromeBand(bottomPadding: session.isActive ? Spacing.xs : 0)
        .onChange(of: focused) { _, isFocused in
            let wasIdle = !session.isActive
            session.focusChanged(isFocused, begin: begin)
            // Like Safari: a session started by tapping the field selects its text.
            if isFocused, wasIdle, !session.text.isEmpty { Self.selectAllInFocusedField() }
        }
        .onChange(of: session.isFocused) { _, wanted in
            if focused != wanted { focused = wanted }
        }
        .onAppear { focused = session.isFocused }
        // The field leaving the screen takes the keyboard with it; the session stays.
        .onDisappear { session.lowerKeyboard() }
    }

    private static func selectAllInFocusedField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }
}

extension View {
    /// Swipe down lowers the keyboard but keeps the search session (text and ✕ stay). For
    /// surfaces that don't scroll; a scrolling list uses `.scrollDismissesKeyboard(.interactively)`.
    func lowersKeyboardOnPullDown(_ session: SearchSession) -> some View {
        modifier(PullDownToLowerKeyboard(session: session))
    }
}

private struct PullDownToLowerKeyboard: ViewModifier {
    let session: SearchSession
    /// Axis of the drag in progress, fixed at its first movement (nil between drags).
    @State private var dragAxis: Axis?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance)
                .onChanged { value in
                    if dragAxis == nil { dragAxis = SwipeGesturePolicy.axis(ofFirstMovement: value.translation) }
                }
                .onEnded { value in
                    let vertical = dragAxis == .vertical
                    dragAxis = nil
                    guard vertical, session.isActive, session.isFocused else { return }
                    if SwipeGesturePolicy.shouldCommitDownwardDismiss(
                        translation: value.translation.height,
                        predicted: value.predictedEndTranslation.height
                    ) {
                        session.lowerKeyboard()
                    }
                }
        )
    }
}
