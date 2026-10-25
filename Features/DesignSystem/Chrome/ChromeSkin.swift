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

    /// The field is in the compact chrome: `ChromeMetrics.barHeight` high, whatever the text size
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
    /// whose controls are its own).
    func chromeSurface<S: InsettableShape>(_ shape: S, fill: Color = Palette.chrome, interactive: Bool = true) -> some View {
        modifier(ChromeSurface(shape: shape, fill: fill, interactive: interactive))
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
    let interactive: Bool
    @Environment(\.chromeSkin) private var skin

    func body(content: Content) -> some View {
        switch skin {
        case .glass:
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                    .glassEffectTransition(.materialize)
            } else {
                content.background(fill, in: shape)
            }
        case .material:
            // The shadow sits under the shape, not under the glyphs.
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(Palette.glass) }
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
