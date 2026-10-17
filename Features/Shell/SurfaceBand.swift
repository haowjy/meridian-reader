import SwiftUI
import UIKit

/// The bottom band the browser and the Library share (decisions D22 and D23): built here once, so
/// it sits at the same height with every control at the same place on both, and swapping surfaces
/// changes only what the controls say.
///
/// ```
/// ╭ Now Playing bar, or the last played, or "Nothing playing"          ╮   ← always there
/// [🌐/📚] ( 🔍 address field / Search Library                          )
/// [‹]  [›]  [＋/🔖]  [🕘]  [⋯]                                            ← same role per slot
/// ```
///
/// Searching (Safari-style), the first row and the toolbar step aside so the field sits on the
/// keyboard, with a round ✕ beside it that ends the session. Lowering the keyboard keeps the
/// session (`lowersKeyboardOnPullDown`). The band owns the field's focus and keeps it in sync with
/// `session.isFocused`.
struct SurfaceBand<Field: View, Toolbar: View>: View {
    /// The swap to the other surface, at the leading edge of the field's row (row 2).
    let swap: BandSwap
    let session: SearchSession
    let cancelID: String
    let onCancel: () -> Void
    /// Text a session starts with when the idle field is tapped.
    var beginText: () -> String = { "" }
    /// The surface is under the Reader sheet, which shows the bar itself.
    var isBarCovered = false
    @ViewBuilder var field: (FocusState<Bool>.Binding) -> Field
    @ViewBuilder var toolbar: () -> Toolbar

    @Environment(\.speechController) private var speech
    /// The field's focus, kept in sync with `session.isFocused`; `field` attaches it to its
    /// `TextField`.
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: BottomChrome.rowSpacing) {
            if !session.isActive {
                // Row 1: Now Playing alone, full width (D23).
                BandNowPlayingBar(speech: speech, isCovered: isBarCovered)
                    .tint(Palette.ink)
                    .padding(.bottom, Spacing.xxs)
            }
            // Row 2: the swap (the toolbar's own button, 44 pt, tight to the leading edge), then
            // the field filling the rest. While searching the swap steps aside with the toolbar,
            // and ✕ ends the search (it stays after a swipe-down lowered the keyboard).
            HStack(spacing: Spacing.xs) {
                BandFieldRow(swap: session.isActive ? nil : swap) {
                    field($focused)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("bandField")
                }
                if session.isActive {
                    Button(action: onCancel) {
                        Image(systemName: Icons.close)
                            .foregroundStyle(Palette.ink)
                            .roundFieldControl(fill: Palette.chrome)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier(cancelID)
                }
            }
            if !session.isActive {
                toolbar()
                    // Tint, not foregroundStyle: a foreground style overrides the dimming SwiftUI
                    // gives disabled buttons, so a slot with nothing to do would look tappable.
                    .tint(Palette.ink)
            }
        }
        .bottomChromeBand(bottomPadding: session.isActive ? Spacing.xs : 0)
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
