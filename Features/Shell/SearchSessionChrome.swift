import SwiftUI
import UIKit

/// The bottom chrome around a search field (browser address bar, library search), Safari-style:
/// idle, the accessory (mini player) sits above the field and the toolbar below it; while a
/// session is active the toolbar steps aside so the field hugs the keyboard, and a round ✕ to
/// its right ends the session. Lowering the keyboard keeps the session (see
/// `lowersKeyboardOnPullDown`).
///
/// The chrome owns the field's focus and keeps it in sync with `session.isFocused`; the caller's
/// `field` builder attaches the binding to its `TextField`.
struct SearchSessionChrome<Accessory: View, Field: View, Toolbar: View>: View {
    let session: SearchSession
    let cancelID: String
    let onCancel: () -> Void
    /// Text a session starts with when the idle field is tapped (selected, so typing replaces it).
    var beginText: () -> String = { "" }
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var field: (FocusState<Bool>.Binding) -> Field
    @ViewBuilder var toolbar: () -> Toolbar

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            if !session.isActive {
                accessory()
            }
            HStack(spacing: 10) {
                field($focused)
                // ✕ stays while searching, even after a swipe-down lowered the keyboard.
                if session.isActive {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color(.secondarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier(cancelID)
                }
            }
            if !session.isActive {
                toolbar()
            }
        }
        .bottomChromeBand(bottomPadding: session.isActive ? 8 : 0)
        .onChange(of: focused) { _, isFocused in
            let wasIdle = !session.isActive
            session.focusChanged(isFocused, beginText: beginText)
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

extension SearchSessionChrome where Accessory == EmptyView {
    init(session: SearchSession, cancelID: String, onCancel: @escaping () -> Void,
         beginText: @escaping () -> String = { "" },
         @ViewBuilder field: @escaping (FocusState<Bool>.Binding) -> Field,
         @ViewBuilder toolbar: @escaping () -> Toolbar) {
        self.init(session: session, cancelID: cancelID, onCancel: onCancel, beginText: beginText,
                  accessory: { EmptyView() }, field: field, toolbar: toolbar)
    }
}

extension View {
    /// Swipe down lowers the keyboard but keeps the search session (text and ✕ stay). For a list
    /// that scrolls, pass whether it's at its top: only a pull that starts there counts.
    func lowersKeyboardOnPullDown(_ session: SearchSession, isAtTop: Bool = true) -> some View {
        modifier(PullDownToLowerKeyboard(session: session, isAtTop: isAtTop))
    }
}

private struct PullDownToLowerKeyboard: ViewModifier {
    let session: SearchSession
    let isAtTop: Bool
    /// Whether the drag in progress began with the list at its top (nil between drags).
    @State private var startedAtTop: Bool?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: SwipeGesturePolicy.verticalMinimumDistance)
                .onChanged { _ in
                    if startedAtTop == nil { startedAtTop = isAtTop }
                }
                .onEnded { value in
                    let fromTop = startedAtTop ?? isAtTop
                    startedAtTop = nil
                    guard session.isActive, session.isFocused, fromTop else { return }
                    if SwipeGesturePolicy.shouldCommitVerticalDismiss(
                        translation: value.translation,
                        predicted: value.predictedEndTranslation
                    ) {
                        session.lowerKeyboard()
                    }
                }
        )
    }
}
