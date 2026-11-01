import SwiftUI

/// The controls floating at the top of every compact reading page (the Browser's reader mode and
/// Library Read in place, and Listen at its top, the grabber between them), one layout on all three:
///
/// ```
/// ( Aa )                          ( ▶ Listen ) ( ⋯ )     in place: ▶, or the playing bars while the page plays
/// ( Aa )                                         ( ⋯ )     Listen
/// ```
///
/// ⋯ (trailing, where every other screen has its ⋯) is the screen's menu as a system menu (`menu`, a
/// section per block); Aa (leading) opens the text appearance panel pointing at it; ▶ Listen, the page's
/// primary action, is an accent-filled capsule just before ⋯, there while `listen` is set (in place,
/// whenever the page has text). Once the page is what you hear it stays, in the same place and size,
/// showing the live state (`ReadingListen.Face`) and only opening Listen. VoiceOver reads them as they
/// sit: Aa, ▶ Listen, ⋯. `Control.chrome` high, as every piece of the bottom
/// chrome (⋯ and Aa are Listen's circle), at least `Control.tap` to tap (`ChromeMetrics.hitOutset` past the glass), `Spacing.xs` apart, in place `Spacing.topBarMargin` from the screen's edges (a navigation bar's buttons'), the chrome's glyph and glass
/// (the material skin before iOS 26). In place it sits on the safe area's
/// top, level with a navigation bar's buttons. On Listen's sheet (`carriesGrabber`) it is the sheet's top, as Voice Memos'
/// is: the grabber centred `Spacing.xs` below the sheet's top edge, the circles' tops `Spacing.m` below it
/// and `Spacing.bandMargin` in from its sides, so they sit inside its rounded corners. It keeps
/// `Spacing.xs` under it: drawn in a reading page's header, the text starts clear below it. It is a reading page's header, so it goes with the bars in full screen (`ReadingBars`).
struct ReadingTopGroup: View {
    /// The screen's menu, a section per block.
    let menu: [[MenuRow]]
    let menuID: String
    /// The text appearance panel is open (Aa lit, pointing at it).
    @Binding var appearanceOpen: Bool
    /// ▶ Listen; nil: none (Listen itself, or a page with no text to read).
    var listen: ReadingListen?
    /// Listen's sheet: the grabber centred between Aa and ⋯, level with their tops.
    var carriesGrabber = false

    @Environment(\.readingPalette) private var reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            appearance
            Spacer(minLength: 0)
            if let listen {
                ListenCapsule(listen: listen)
                    .transition(.opacity)
            }
            TitleMenuButton(id: menuID, blocks: menu) {
                ChromeCircleFace(symbol: Icons.more, label: Verbs.more)
                    .frame(width: Control.chrome, height: Control.chrome)
            }
        }
        .padding(.horizontal, carriesGrabber ? Spacing.bandMargin : Spacing.topBarMargin)
        .padding(.top, carriesGrabber ? Spacing.m : 0)
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
            .frame(width: Control.chrome, height: Control.chrome)
        }
        .buttonStyle(.plain)
        .textAppearancePopover(isPresented: $appearanceOpen)
        .accessibilityLabel(Verbs.textAppearance)
        .accessibilityIdentifier("readerAppearance")
    }
}

/// The top group's ▶ Listen: what it shows and what its tap does.
struct ReadingListen {
    enum Face {
        /// The page isn't what you hear: ▶ plays it and opens Listen.
        case start
        /// The page is what you hear, playing (the playing bars) or paused (▶): the tap only opens Listen.
        case playing, paused
    }

    var face: Face
    var action: () -> Void
}

/// ▶ Listen: the chrome's glyph (or the playing bars, in the glyph's slot so the capsule keeps its width)
/// and its worded pieces' type on an accent-filled capsule.
private struct ListenCapsule: View {
    let listen: ReadingListen

    @Environment(\.readingPalette) private var reading

    var body: some View {
        Button(action: listen.action) {
            HStack(spacing: Spacing.xs) {
                Group {
                    if listen.face == .playing {
                        PlayingBars(animating: true)
                            .frame(height: Glyph.small)
                    } else {
                        Image(systemName: Icons.play)
                            .font(BottomChrome.chromeGlyph)
                    }
                }
                .frame(width: Glyph.regular)
                Text(Verbs.listen)
                    .typeStyle(.row, weight: .semibold)
                    // A fixed-height piece: past XXXL the word would clip.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(reading?.onAccent ?? Palette.onAccent)
            .padding(.horizontal, Spacing.m)
            .frame(height: Control.chrome)
            .contentShape(Capsule().inset(by: -ChromeMetrics.hitOutset))
            .chromeSurface(Capsule(), tint: reading?.accent ?? Palette.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listen.face == .start ? Verbs.listen : Verbs.openListen)
        .accessibilityValue(listen.face == .playing ? String(localized: "Playing") : "")
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
            PreviewState("in place, not what you hear") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, listen: ReadingListen(face: .start) {})
            }
            PreviewState("in place, playing") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, listen: ReadingListen(face: .playing) {})
            }
            PreviewState("in place, paused") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, listen: ReadingListen(face: .paused) {})
            }
            PreviewState("Listen's sheet top, the grabber between") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, carriesGrabber: true)
            }
            PreviewState("on a reading theme") {
                ReadingTopGroup(menu: menu, menuID: "previewMore", appearanceOpen: $open, listen: ReadingListen(face: .start) {})
                    .onReadingPreview(.sepia)
            }
        }
    }
}

#Preview("ReadingTopGroup · light", traits: .sizeThatFitsLayout) { ReadingTopGroupGallery().previewVariant(.light) }
#Preview("ReadingTopGroup · dark", traits: .sizeThatFitsLayout) { ReadingTopGroupGallery().previewVariant(.dark) }
#Preview("ReadingTopGroup · AX5", traits: .sizeThatFitsLayout) { ReadingTopGroupGallery().previewVariant(.largestText) }
#endif
