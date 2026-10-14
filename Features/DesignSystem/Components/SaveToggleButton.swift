import SwiftUI

/// 🔖 in a toolbar slot: the Reader's slot 1 and the browser's slot 3. Tap saves to the Library
/// (or removes what is saved); long-press picks a folder (*Save to Folder…*), and a tap released
/// early still saves. A spinner stands in while the save is under way.
///
/// ```
/// [🔖]  not saved      [🔖̲]  saved (filled, accent)      [◌]  saving
/// ```
struct SaveToggleButton: View {
    let isSaved: Bool
    var isBusy = false
    let identifier: String
    let onToggle: () -> Void
    /// Long-press → *Save to Folder…* (nil: no long-press).
    var onSaveToFolder: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: onToggle) {
            Group {
                if isBusy {
                    ProgressView()
                } else if isSaved {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(Palette.accent)
                } else {
                    Image(systemName: "bookmark")
                        .foregroundStyle(Palette.ink)
                }
            }
            // Disabled (no page), it dims like ‹ and ›; the spinner shows in full.
            .opacity(isEnabled || isBusy ? 1 : Palette.disabledOpacity)
            .toolbarIconFrame()
        }
        .buttonStyle(GlyphButtonStyle())
        .highPriorityGesture(
            LongPressGesture().onEnded { _ in onSaveToFolder?() },
            including: onSaveToFolder == nil ? .subviews : .all
        )
        .accessibilityLabel(isSaved ? "Remove from Library" : "Save")
        .accessibilityValue(isBusy ? "Saving" : isSaved ? "Saved" : "Not saved")
        .accessibilityIdentifier(identifier)
        .accessibilityActions {
            if let onSaveToFolder {
                Button("Save to Folder…", action: onSaveToFolder)
            }
        }
    }
}

/// The label as laid out, fading while pressed. It leaves dimming to the button (a system style
/// would dim a disabled 🔖 a second time, fainter than ‹ and ›).
private struct GlyphButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Palette.pressedOpacity : 1)
    }
}

#if DEBUG
struct SaveToggleButtonGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("not saved") { button(saved: false) }
            PreviewState("saved") { button(saved: true) }
            PreviewState("saving") { button(saved: false, busy: true) }
            PreviewState("disabled") { button(saved: false).disabled(true) }
        }
    }

    private func button(saved: Bool, busy: Bool = false) -> some View {
        SaveToggleButton(isSaved: saved, isBusy: busy, identifier: "preview", onToggle: {}, onSaveToFolder: {})
            .frame(width: 80)
            .tint(Palette.ink)
    }
}

#Preview("SaveToggleButton · light", traits: .sizeThatFitsLayout) { SaveToggleButtonGallery().previewVariant(.light) }
#Preview("SaveToggleButton · dark", traits: .sizeThatFitsLayout) { SaveToggleButtonGallery().previewVariant(.dark) }
#Preview("SaveToggleButton · AX5", traits: .sizeThatFitsLayout) { SaveToggleButtonGallery().previewVariant(.largestText) }
#endif
