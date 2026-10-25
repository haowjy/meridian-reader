import SwiftUI

/// What the compact bottom chrome (`ChromeHost`) is drawn on. The layout, the controls and the
/// state machine are the same in every skin; only the surface behind each control differs.
enum ChromeSkin: Equatable {
    /// Every other chrome (the regular-width band, the Reader's band): today's `.bar` band with
    /// `Palette.chrome` capsules. The environment's default, so nothing outside the compact chrome changes.
    case system
    /// iOS 26: each control is its own Liquid Glass shape, all inside one `GlassEffectContainer`.
    case glass
    /// Earlier iOS: one thick material strip behind the rows, `Palette.chrome` capsules on it.
    case strip

    #if DEBUG
    /// `-chromeFallback`: the strip on a new OS too, to check it. Set by the launch (`AppMain`).
    static var forcesStrip = false
    #endif

    /// The skin the compact chrome uses: glass on iOS 26 and later, the strip before that.
    static var current: ChromeSkin {
        #if DEBUG
        if forcesStrip { return .strip }
        #endif
        if #available(iOS 26.0, *) { return .glass }
        return .strip
    }
}

private struct ChromeSkinKey: EnvironmentKey {
    static let defaultValue = ChromeSkin.system
}

private struct ChromeFieldHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private struct ChromeFieldCollapsedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var chromeSkin: ChromeSkin {
        get { self[ChromeSkinKey.self] }
        set { self[ChromeSkinKey.self] = newValue }
    }

    /// The height the compact chrome gives a field capsule (nil: the field's own, 44 pt at the
    /// default text size).
    var chromeFieldHeight: CGFloat? {
        get { self[ChromeFieldHeightKey.self] }
        set { self[ChromeFieldHeightKey.self] = newValue }
    }

    /// The compact chrome is one row: its address field shows the address alone (the reader icon
    /// and reload step aside, the field itself is the tap target).
    var chromeFieldCollapsed: Bool {
        get { self[ChromeFieldCollapsedKey.self] }
        set { self[ChromeFieldCollapsedKey.self] = newValue }
    }
}

extension View {
    /// A chrome control's surface in `shape`: glass, or `fill` on the strip and the old band.
    /// `interactive` makes a button's glass answer a press.
    func chromeSurface<S: Shape>(_ shape: S, fill: Color = Palette.chrome, interactive: Bool = false) -> some View {
        modifier(ChromeSurface(shape: shape, fill: fill, interactive: interactive))
    }
}

private struct ChromeSurface<S: Shape>: ViewModifier {
    let shape: S
    let fill: Color
    let interactive: Bool
    @Environment(\.chromeSkin) private var skin

    func body(content: Content) -> some View {
        if skin == .glass, #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else if skin == .strip {
            // The fallback gives every piece the same rim and lift glass has: one hairline, one soft shadow.
            content
                .background(fill, in: shape)
                .overlay { shape.stroke(Palette.ink.opacity(0.1), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        } else {
            content.background(fill, in: shape)
        }
    }
}

extension View {
    /// Gives the glass shape an identity inside a `GlassEffectContainer`, so two shapes that share
    /// `id` (the pill and the collapsed icon) morph into each other as one is swapped for the other.
    func chromeMorph(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(ChromeMorph(id: id, namespace: namespace))
    }

    /// The container glass shapes blend and morph in: one for all of the compact chrome.
    func chromeGlassContainer() -> some View {
        modifier(ChromeGlassContainer())
    }
}

private struct ChromeMorph: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.chromeSkin) private var skin

    func body(content: Content) -> some View {
        if skin == .glass, #available(iOS 26.0, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
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
