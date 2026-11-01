import SwiftUI

/// The controls floating at the top of every compact reading page (the Browser's reader mode and
/// Library Read in place, and Listen at its top, the grabber between them), one layout on all three:
///
/// ```
/// ( ⋯ )                          ( Aa ) ( ▶ Listen )     in place, the page not what you hear
/// ( ⋯ )                                         ( Aa )     in place once it is, and Listen
/// ```
///
/// ⋯ (leading) is the screen's menu as a system menu (`menu`, a section per block); Aa opens the text
/// appearance panel pointing at it; ▶ Listen, the page's primary action, is an accent-filled capsule
/// at the trailing end, there only while `listen` is set. `ChromeMetrics.innerCircle` high (40 pt, the
/// address field's lit reader icon: the bottom chrome's 48 reads larger alone on the page), tapped 44 pt
/// (`innerHitOutset` past the glass), `Spacing.xs` apart, `Spacing.bandMargin` from the screen's edges, the chrome's glyph and glass
/// (the material skin before iOS 26), so its hit areas are the glass itself. In place it sits `Spacing.xs`
/// below the status bar. On Listen's sheet (`carriesGrabber`) it is the sheet's top, as Voice Memos'
/// is: the grabber centred `Spacing.xs` below the sheet's top edge, the circles' tops `Spacing.m` below it
/// and `Spacing.bandMargin` in from its sides, so they sit inside its rounded corners. It keeps
/// `Spacing.xs` under it: drawn in a reading page's header, the text starts clear below it. It is a reading page's header, so it goes with the bars in full screen (`ReadingBars`).
struct ReadingTopGroup: View {
    /// The screen's menu, a section per block.
    let menu: [[MenuRow]]
    let menuID: String
    /// The text appearance panel is open (Aa lit, pointing at it).
    @Binding var appearanceOpen: Bool
    /// ▶ Listen's tap; nil: no ▶ Listen (the page is what you hear, or Listen itself).
    var listen: (() -> Void)?
    /// Listen's sheet: the grabber centred between ⋯ and Aa, level with their tops.
    var carriesGrabber = false

    @Environment(\.readingPalette) private var reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            TitleMenuButton(id: menuID, blocks: menu) {
                ChromeCircleFace(symbol: Icons.more, label: Verbs.more)
                    .frame(width: ChromeMetrics.innerCircle, height: ChromeMetrics.innerCircle)
            .contentShape(Rectangle().inset(by: -ChromeMetrics.innerHitOutset))
            }
            Spacer(minLength: 0)
            appearance
            if let listen {
                ListenCapsule(action: listen)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.bandMargin)
        .padding(.top, carriesGrabber ? Spacing.m : Spacing.xs)
        .padding(.bottom, Spacing.xs)
        .overlay(alignment: .top) {
            if carriesGrabber { SheetGrabber().padding(.top, Spacing.xs) }
        }
        .chromeGlassContainer()
        .environment(\.chromeSkin, ChromeSkin.current)
        .animation(reduceMotion ? nil : Motion.snappy, value: listen == nil)
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
            .frame(width: ChromeMetrics.innerCircle, height: ChromeMetrics.innerCircle)
            .contentShape(Rectangle().inset(by: -ChromeMetrics.innerHitOutset))
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
            .frame(height: ChromeMetrics.innerCircle)
            .contentShape(Capsule().inset(by: -ChromeMetrics.innerHitOutset))
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
            PreviewState("in place, playing") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open)
            }
            PreviewState("Listen's sheet top, the grabber between") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, carriesGrabber: true)
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
