import SwiftUI

/// What the compact bottom chrome (`ChromeHost`) is drawn on. The layout, the controls and the
/// state machine are the same in every skin; only the surface of each piece differs, and none of
/// them has a plate behind the pieces: the page shows through.
enum ChromeSkin: Equatable {
    /// Every other chrome (the regular-width band): `Palette.chrome` capsules. The environment's
    /// default, so nothing outside the compact chrome changes.
    case system
    /// iOS 26: each piece is its own Liquid Glass shape, all inside one `GlassEffectContainer`.
    case glass
    /// Earlier iOS: a blur with the glass tint over it (`Palette.glass`), an inner rim and a soft
    /// shadow, so a piece looks like the glass.
    case material

    #if DEBUG
    /// `-chromeFallback`: the material skin on a new OS too, to check it. Set by the launch (`AppMain`).
    static var forcesMaterial = false
    #endif

    /// The skin the compact chrome uses: glass on iOS 26 and later, the material before that.
    static var current: ChromeSkin {
        #if DEBUG
        if forcesMaterial { return .material }
        #endif
        if #available(iOS 26.0, *) { return .glass }
        return .material
    }
}

private struct ChromeSkinKey: EnvironmentKey {
    static let defaultValue = ChromeSkin.system
}

private struct IsChromeFieldKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ChromeFieldWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var chromeSkin: ChromeSkin {
        get { self[ChromeSkinKey.self] }
        set { self[ChromeSkinKey.self] = newValue }
    }

    /// The field is in the compact chrome: `Control.chrome` high, whatever the text size
    /// (elsewhere its own, 44 pt at the default text size).
    var isChromeField: Bool {
        get { self[IsChromeFieldKey.self] }
        set { self[IsChromeFieldKey.self] = newValue }
    }

    /// The width the chrome gives its field right now (it changes every frame of a fold): the
    /// address field shows its reader icon and reload by it. nil outside the chrome.
    var chromeFieldWidth: CGFloat? {
        get { self[ChromeFieldWidthKey.self] }
        set { self[ChromeFieldWidthKey.self] = newValue }
    }
}

extension View {
    /// A chrome piece's surface in `shape`: glass, the material look, or `fill` on the old band.
    /// Every chrome piece is tappable, so its glass answers a press (`interactive`; not a card
    /// whose controls are its own). `tint`: a primary action's colour (the reading pages' ▶ Listen),
    /// the glass tinted with it, the material filled with it.
    func chromeSurface<S: InsettableShape>(_ shape: S, fill: Color = Palette.chrome, tint: Color? = nil,
                                           interactive: Bool = true) -> some View {
        modifier(ChromeSurface(shape: shape, fill: tint ?? fill, tint: tint, interactive: interactive))
    }

    /// The chrome's fixed-size glyphs don't grow with text; a long press shows this one large.
    func chromeLargeContent(_ label: String, symbol: String) -> some View {
        accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }

    /// The container glass shapes blend in: one for all of the compact chrome.
    func chromeGlassContainer() -> some View {
        modifier(ChromeGlassContainer())
    }
}

private struct ChromeSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let tint: Color?
    let interactive: Bool
    @Environment(\.chromeSkin) private var skin

    func body(content: Content) -> some View {
        switch skin {
        case .glass:
            if #available(iOS 26.0, *) {
                let glass = Glass.regular.tint(tint)
                content
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                    .glassEffectTransition(.materialize)
            } else {
                content.background(fill, in: shape)
            }
        case .material:
            // The shadow sits under the shape, not under the glyphs.
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(tint ?? Palette.glass) }
                        .shadow(color: Palette.glassShadow, radius: 11, y: 6)
                }
                .overlay { shape.strokeBorder(Palette.glassEdge, lineWidth: 0.5) }
        case .system:
            content.background(fill, in: shape)
        }
    }
}

private struct ChromeGlassContainer: ViewModifier {
    @Environment(\.chromeSkin) private var skin

    func body(content: Content) -> some View {
        if skin == .glass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { content }
        } else {
            content
        }
    }
}

/// The chrome's round button face: `content` (a glyph, the playing bars) in the chrome glyph's size and
/// ink, centred on a glass circle that fills the frame it is given, tapped `hitOutset` past it. The
/// chrome's Listen and the reading pages' ⋯ and Aa (`ReadingTopGroup`) are this; each button keeps
/// its own action and accessibility.
struct ChromeCircleFace<Content: View>: View {
    /// What the glyph is called, and its symbol, for the large content viewer.
    let label: String
    let symbol: String
    @ViewBuilder var content: Content

    @Environment(\.readingPalette) private var reading

    var body: some View {
        content
            .font(BottomChrome.chromeGlyph)
            .foregroundStyle(reading?.ink ?? Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(ChromeHitShape())
            .chromeSurface(Circle(), fill: BottomChrome.fieldFill(reading))
            .chromeLargeContent(label, symbol: symbol)
    }
}

extension ChromeCircleFace where Content == Image {
    init(symbol: String, label: String) {
        self.init(label: label, symbol: symbol) { Image(systemName: symbol) }
    }
}

/// A chrome control's hit area: `hitOutset` past its glass above and below, and at each side `leading` /
/// `trailing` past it: `hitOutset` by default, none where a neighbour shares the glass (the pill's segments
/// meet edge to edge), more where one must make up the width (‹ ›, `ChromeMetrics.arrowHitSides`).
struct ChromeHitShape: Shape {
    var leading = ChromeMetrics.hitOutset
    var trailing = ChromeMetrics.hitOutset

    /// A segment of one capsule: only above and below.
    static let segment = ChromeHitShape(leading: 0, trailing: 0)

    func path(in rect: CGRect) -> Path {
        let o = ChromeMetrics.hitOutset
        return Path(CGRect(x: rect.minX - leading, y: rect.minY - o,
                           width: rect.width + leading + trailing, height: rect.height + 2 * o))
    }
}
