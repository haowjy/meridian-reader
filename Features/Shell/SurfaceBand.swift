import SwiftUI

/// The bottom band the browser and the Library share (decision D22): built here once, so it sits
/// at the same height with every control at the same place on both, and swapping surfaces
/// changes only what the controls say.
///
/// ```
/// ╭ Now Playing bar, or the last played, or "Nothing playing"          ╮   ← always there
/// [🌐/📚] ( 🔍 address field / Search Library                          )
/// [‹]  [›]  [＋/🔖]  [🕘]  [⋯]                                            ← same role per slot
/// ```
///
/// Searching (`SearchSessionChrome`), the first row and the toolbar step aside so the field sits
/// on the keyboard, with ✕ beside it.
struct SurfaceBand<Field: View, Toolbar: View>: View {
    /// The swap to the other surface, in slot 1 of the first row.
    struct Swap {
        let systemImage: String
        let label: String
        let hint: String
        let identifier: String
        let action: () -> Void
    }

    let swap: Swap
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

    var body: some View {
        SearchSessionChrome(session: session, cancelID: cancelID, onCancel: onCancel, beginText: beginText) {
            // Row 1: Now Playing alone, full width (D23).
            BandNowPlayingBar(speech: speech, isCovered: isBarCovered)
                .tint(Palette.ink)
                .padding(.bottom, Spacing.xxs)
        } field: { focus in
            // Row 2: the swap (the toolbar's own button, 44 pt, tight to the leading edge), then
            // the field filling the rest. While searching the swap steps aside with the toolbar.
            HStack(spacing: Spacing.xxs) {
                if !session.isActive {
                    BandToolbarButton(systemImage: swap.systemImage, label: swap.label,
                                      identifier: swap.identifier, weight: .light, action: swap.action)
                        .accessibilityHint(swap.hint)
                        .frame(width: BottomChrome.rowHeight, height: BottomChrome.rowHeight)
                        .tint(Palette.ink)
                }
                field(focus)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("bandField")
            }
        } toolbar: {
            toolbar()
                // Tint, not foregroundStyle: a foreground style overrides the dimming SwiftUI
                // gives disabled buttons, so a slot with nothing to do would look tappable.
                .tint(Palette.ink)
        }
    }
}

/// A plain icon in a band toolbar slot.
struct BandToolbarButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    /// Optical weight for line-dense glyphs (the swap); the toolbar slots keep the default.
    var weight: Font.Weight = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).toolbarIconFrame().fontWeight(weight)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
