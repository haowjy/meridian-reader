import SwiftUI

/// The controls floating at the top of every compact reading page (the Browser's reader mode and
/// Library Read in place, and Listen under its grabber), one layout on all three:
///
/// ```
/// ( ⋯ )                          ( Aa ) ( ▶ Listen )     in place, the page not what you hear
/// ( ⋯ )                                         ( Aa )     in place once it is, and Listen
/// ```
///
/// ⋯ (leading) is the screen's menu as a system menu (`menu`, a section per block); Aa opens the text
/// appearance panel pointing at it; ▶ Listen, the page's primary action, is an accent-filled capsule
/// at the trailing end, there only while `listen` is set. The bottom chrome's pieces: `Control.bar`
/// high, `Spacing.xs` apart, `Spacing.bandMargin` from the screen's edges, the chrome's glyph and glass
/// (the material skin before iOS 26), so its hit areas are the glass itself. It sits `Spacing.xs` below
/// what is above it and keeps `Spacing.xs` under it: drawn in a reading page's header, the text starts
/// clear below it.
///
/// `shows` fades it out and back (the compact chrome's fold: gone with the chrome on a scroll down,
/// back with it); the opacity is outside the glass container, so the glass fades too.
struct ReadingTopGroup: View {
    /// The screen's menu, a section per block.
    let menu: [[MenuRow]]
    let menuID: String
    /// The text appearance panel is open (Aa lit, pointing at it).
    @Binding var appearanceOpen: Bool
    /// ▶ Listen's tap; nil: no ▶ Listen (the page is what you hear, or Listen itself).
    var listen: (() -> Void)?
    var shows = true

    @Environment(\.readingPalette) private var reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            TitleMenuButton(id: menuID, blocks: menu) {
                ChromeCircleFace(symbol: Icons.more, label: Verbs.more)
                    .frame(width: Control.bar, height: Control.bar)
            }
            Spacer(minLength: 0)
            appearance
            if let listen {
                ListenCapsule(action: listen)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.bandMargin)
        .padding(.vertical, Spacing.xs)
        .chromeGlassContainer()
        .environment(\.chromeSkin, ChromeSkin.current)
        .animation(reduceMotion ? nil : Motion.snappy, value: listen == nil)
        // Outside the container: an opacity inside it would leave the glass showing.
        .opacity(shows ? 1 : 0)
        .allowsHitTesting(shows)
        .accessibilityHidden(!shows)
        .animation(shows ? Motion.fadeIn : Motion.fadeOut, value: shows)
        .accessibilityElement(children: .contain)
        // Drawn over the text, after it: VoiceOver reads it first, as it sits.
        .accessibilitySortPriority(1)
    }

    private var appearance: some View {
        Button { appearanceOpen.toggle() } label: {
            ChromeCircleFace(label: Verbs.textAppearance, symbol: Icons.textAppearance) {
                // Lit while its panel is open.
                Image(systemName: Icons.textAppearance)
                    .foregroundStyle(appearanceOpen ? reading?.accent ?? Palette.accent : reading?.ink ?? Palette.ink)
            }
            .frame(width: Control.bar, height: Control.bar)
        }
        .buttonStyle(.plain)
        .textAppearancePopover(isPresented: $appearanceOpen)
        .accessibilityLabel(Verbs.textAppearance)
        .accessibilityIdentifier("readerAppearance")
    }
}

/// ▶ Listen: the chrome's glyph and its worded pieces' type on an accent-filled capsule.
private struct ListenCapsule: View {
    let action: () -> Void

    @Environment(\.readingPalette) private var reading

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: Icons.play)
                    .font(BottomChrome.chromeGlyph)
                Text(Verbs.listen)
                    .typeStyle(.row, weight: .semibold)
                    // A fixed-height piece: past XXXL the word would clip.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(reading?.onAccent ?? Palette.onAccent)
            .padding(.horizontal, Spacing.m)
            .frame(height: Control.bar)
            .contentShape(Capsule())
            .chromeSurface(Capsule(), tint: reading?.accent ?? Palette.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Verbs.listen)
        .accessibilityIdentifier("inPlaceListen")
        .chromeLargeContent(Verbs.listen, symbol: Icons.play)
    }
}

#if DEBUG
struct ReadingTopGroupGallery: View {
    @State private var open = false
    private let menu = [[MenuRow(id: "a", title: "Save to Folder…", icon: Icons.newFolder)]]

    var body: some View {
        PreviewGallery {
            PreviewState("in place, not playing") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, listen: {})
            }
            PreviewState("in place, playing; Listen") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open)
            }
            PreviewState("on a reading theme") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, listen: {})
                    .onReadingPreview(.sepia)
            }
        }
    }
}

#Preview("ReadingTopGroup · light", traits: .sizeThatFitsLayout) { ReadingTopGroupGallery().previewVariant(.light) }
#Preview("ReadingTopGroup · dark", traits: .sizeThatFitsLayout) { ReadingTopGroupGallery().previewVariant(.dark) }
#Preview("ReadingTopGroup · AX5", traits: .sizeThatFitsLayout) { ReadingTopGroupGallery().previewVariant(.largestText) }
#endif
