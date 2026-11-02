import SwiftUI

/// A thin accent pill floating in the middle of the line just above what floats at a reading
/// page's foot (the card, or the strip in full screen), in the pills' type (row, semibold) with
/// `Spacing.xs` above and below: Listen's "↑ Jump to Audio". It fades in and out with `shows`, in
/// full screen too, where it stays with the floating play / pause.
///
/// While it shows, Scroll mode's text leaves its line clear at the end
/// (`ReadingChrome.overTextClearance`). It comes and goes with the audio, so Pages' card keeps still
/// and it may float over the card's foot.
struct OverTextPill: View {
    let label: String
    let symbol: String
    let shows: Bool
    var hint = ""
    let identifier: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingPalette) private var reading
    @Environment(\.readingChrome) private var chrome

    var body: some View {
        ZStack {
            if shows {
                Button(action: action) {
                    Label(label, systemImage: symbol)
                        .typeStyle(.row, weight: .semibold)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(reading?.onAccent ?? Palette.onAccent)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xs)
                        // It floats over the text: past XXXL it would hide whole lines of it.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .background(reading?.accent ?? Palette.accent, in: Capsule(style: .continuous))
                        // Its tap area reaches the tap floor.
                        .contentShape(Capsule().inset(by: -Spacing.xxs))
                }
                .buttonStyle(PillPressStyle())
                .accessibilityLabel(label)
                .accessibilityHint(hint)
                .accessibilityIdentifier(identifier)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        // The text's end stays clear of the pill while it shows (0 tall when it doesn't).
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            chrome?.overTextClearance = height > 0 ? height + Spacing.s : 0
        }
        // Reduce Motion: a cross-fade, no spring.
        .animation(shows ? (reduceMotion ? Motion.fadeIn : Motion.snappy) : Motion.fadeOut, value: shows)
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
            PreviewState("Jump to Audio, on a reading theme") {
                OverTextPill(label: Verbs.jumpToAudio, symbol: Icons.jumpToAudioDown, shows: true, identifier: "previewJumpDown") {}
                    .environment(\.readingPalette, ReadingTheme.sepia.palette(accent: .jade))
            }
        }
    }
}

#Preview("OverTextPill · light", traits: .sizeThatFitsLayout) { OverTextPillGallery().previewVariant(.light) }
#Preview("OverTextPill · dark", traits: .sizeThatFitsLayout) { OverTextPillGallery().previewVariant(.dark) }
#Preview("OverTextPill · AX5", traits: .sizeThatFitsLayout) { OverTextPillGallery().previewVariant(.largestText) }
#endif
