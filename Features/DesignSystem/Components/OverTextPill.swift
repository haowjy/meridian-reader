import SwiftUI

/// A thin accent pill floating in the middle of the line just above what floats at a reading
/// page's foot (the card, the compact chrome, or the strip in full screen), in the pills' type
/// (row, semibold) with just 4 pt above and below: Listen's "↑ Jump to Audio" and the in-place
/// readers' "▶ Listen", one look for both. It fades in and out with `shows`; in full screen only
/// with the floating play / pause (`ReadingChrome.showsFloating`), so the two come and go together.
///
/// While it shows, Scroll mode's text leaves its line clear at the end
/// (`ReadingChrome.overTextClearance`). A pill that stays while the page shows (`holdsPagesRoom`:
/// the in-place readers' Listen) has Pages' card end above it too (`ReadingChrome.pageCardClearance`);
/// Jump to Audio comes and goes with the audio, so the card keeps still and it may float over the
/// card's foot.
struct OverTextPill: View {
    let label: String
    let symbol: String
    let shows: Bool
    var hint = ""
    let identifier: String
    var holdsPagesRoom = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingPalette) private var reading
    @Environment(\.readingChrome) private var chrome

    private var visible: Bool {
        guard shows, let chrome, chrome.hidden else { return shows }
        return chrome.showsFloating
    }

    var body: some View {
        ZStack {
            if visible {
                Button(action: action) {
                    Label(label, systemImage: symbol)
                        .typeStyle(.row, weight: .semibold)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(reading?.onAccent ?? Palette.onAccent)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xxs)
                        .background(reading?.accent ?? Palette.accent, in: Capsule(style: .continuous))
                        // Thin, but its tap area is the tap floor.
                        .contentShape(Capsule().inset(by: -Spacing.s))
                }
                .buttonStyle(PillPressStyle())
                .accessibilityLabel(label)
                .accessibilityHint(hint)
                .accessibilityIdentifier(identifier)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        // The text's end (and, holding Pages' room, the card) stays clear of the pill while it
        // shows (0 tall when it doesn't).
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            let clearance = height > 0 ? height + Spacing.s : 0
            chrome?.overTextClearance = clearance
            if holdsPagesRoom { chrome?.pageCardClearance = clearance }
        }
        // Reduce Motion: a cross-fade, no spring.
        .animation(visible ? (reduceMotion ? Motion.fadeIn : Motion.snappy) : Motion.fadeOut, value: visible)
    }
}

#if DEBUG
struct OverTextPillGallery: View {
    var body: some View {
        PreviewGallery {
            PreviewState("Jump to Audio") {
                OverTextPill(label: Verbs.jumpToAudio, symbol: Icons.jumpToAudioUp, shows: true,
                             identifier: "previewJump") {}
            }
            PreviewState("Listen, on a reading theme") {
                OverTextPill(label: Verbs.listen, symbol: Icons.play, shows: true, identifier: "previewListen") {}
                    .environment(\.readingPalette, ReadingTheme.sepia.palette(accent: .jade))
            }
        }
    }
}

#Preview("OverTextPill · light", traits: .sizeThatFitsLayout) { OverTextPillGallery().previewVariant(.light) }
#Preview("OverTextPill · dark", traits: .sizeThatFitsLayout) { OverTextPillGallery().previewVariant(.dark) }
#Preview("OverTextPill · AX5", traits: .sizeThatFitsLayout) { OverTextPillGallery().previewVariant(.largestText) }
#endif
