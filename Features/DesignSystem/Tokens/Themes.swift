import SwiftUI
import UIKit

/// The app's theme: its appearance (System, Light, Dark) and its colour (`AccentTheme`), chosen in
/// Settings › Appearance (`AppAppearance`). Every surface draws from `Palette`, whose accent tokens
/// read the colour chosen; the appearance is the windows' interface style.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app's colour: the accent and what is drawn from it (the playing tint, letter tiles). Paper
/// and ink stay neutral in every theme. Each value keeps 4.5:1 as text on `paper`, `chrome` and its
/// own playing tint, and its `onAccent` 4.5:1 on it; check a new or changed theme's ratios.
///
/// | Theme | accent | playingTint | placeholderTile | placeholderInk |
/// |---|---|---|---|---|
/// | Jade | #287060 / #5FB8A0 | #E6F1ED / #163029 | #D5E6DF / #2A4A42 | #1F5A4D / #D5EDE5 |
/// | Harbor | #2B5F8E / #7AAEDD | #E2E7EA / #28333E | #CDD8E0 / #334252 | #20476A / #AFCEEB |
/// | Plum | #7B3F7A / #C892C6 | #ECE4E8 / #382D39 | #DFD1DC / #4A3A4B | #5C2F5C / #DEBEDD |
/// | Ember | #9A4A1E / #E8956A | #EFE5DD / #3E2E27 | #E6D3C7 / #543B2F | #743816 / #F1BFA6 |
/// | Graphite | #45505C / #A7B2BE | #E5E6E4 / #313438 | #D3D5D5 / #404348 | #343C45 / #CAD1D8 |
///
/// `onAccent` is white in light and #141416 in dark for all of them.
enum AccentTheme: String, CaseIterable, Identifiable {
    case jade, harbor, plum, ember, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jade: String(localized: "Jade")
        case .harbor: String(localized: "Harbor")
        case .plum: String(localized: "Plum")
        case .ember: String(localized: "Ember")
        case .graphite: String(localized: "Graphite")
        }
    }

    var accent: Color {
        switch self {
        case .jade: Color(light: 0x287060, dark: 0x5FB8A0)
        case .harbor: Color(light: 0x2B5F8E, dark: 0x7AAEDD)
        case .plum: Color(light: 0x7B3F7A, dark: 0xC892C6)
        case .ember: Color(light: 0x9A4A1E, dark: 0xE8956A)
        case .graphite: Color(light: 0x45505C, dark: 0xA7B2BE)
        }
    }

    var onAccent: Color { Color(light: 0xFFFFFF, dark: 0x141416) }

    var playingTint: Color {
        switch self {
        case .jade: Color(light: 0xE6F1ED, dark: 0x163029)
        case .harbor: Color(light: 0xE2E7EA, dark: 0x28333E)
        case .plum: Color(light: 0xECE4E8, dark: 0x382D39)
        case .ember: Color(light: 0xEFE5DD, dark: 0x3E2E27)
        case .graphite: Color(light: 0xE5E6E4, dark: 0x313438)
        }
    }

    var placeholderTile: Color {
        switch self {
        case .jade: Color(light: 0xD5E6DF, dark: 0x2A4A42)
        case .harbor: Color(light: 0xCDD8E0, dark: 0x334252)
        case .plum: Color(light: 0xDFD1DC, dark: 0x4A3A4B)
        case .ember: Color(light: 0xE6D3C7, dark: 0x543B2F)
        case .graphite: Color(light: 0xD3D5D5, dark: 0x404348)
        }
    }

    var placeholderInk: Color {
        switch self {
        case .jade: Color(light: 0x1F5A4D, dark: 0xD5EDE5)
        case .harbor: Color(light: 0x20476A, dark: 0xAFCEEB)
        case .plum: Color(light: 0x5C2F5C, dark: 0xDEBEDD)
        case .ember: Color(light: 0x743816, dark: 0xF1BFA6)
        case .graphite: Color(light: 0x343C45, dark: 0xCAD1D8)
        }
    }
}

/// The reading page's colours, apart from the app's (Settings › Reading, the Aa panel): one token
/// set for the Reader and Now Playing alike (`ReadingPalette`). *Match App* is the app's paper and
/// ink in its appearance and colour; the others keep their colours whatever the app's appearance.
/// Light, Dark and Black take the app's accent (its light or dark value); Sepia has its own.
enum ReadingTheme: String, CaseIterable, Identifiable {
    case matchApp, light, sepia, dark, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matchApp: String(localized: "Match App")
        case .light: String(localized: "Light")
        case .sepia: String(localized: "Sepia")
        case .dark: String(localized: "Dark")
        case .black: String(localized: "Black")
        }
    }

    /// The colours, with `accent` the app's colour.
    ///
    /// | Theme | background | card | ink | secondary | tertiary | dimmed | accent (= underline) | highlight |
    /// |---|---|---|---|---|---|---|---|---|
    /// | Match App | paper | chrome | ink | secondaryInk | tertiaryInk | #707077 / #87878F | accent | playingTint |
    /// | Light | #FFFFFF | #F2F2F4 | #1A1A1C | #55555E | #6B6B74 | #75757C | accent (light) | accent 10% |
    /// | Sepia | #F4ECD8 | #EADFC6 | #3B2F22 | #5E4D3A | #6B5944 | #6F5F4C | #8A4B1C | #E7D9C1 |
    /// | Dark | #1C1C1E | #2C2C2E | #ECEAE5 | #A3A3AB | #96969F | #8D8D95 | accent (dark) | accent 16% |
    /// | Black | #000000 | #1A1A1C | #E4E4E4 | #9E9EA6 | #8E8E96 | #7C7C84 | accent (dark) | accent 18% |
    func palette(accent: AccentTheme) -> ReadingPalette {
        switch self {
        case .matchApp:
            return ReadingPalette(
                theme: self, colorScheme: nil,
                background: Palette.paper, card: Palette.chrome, ink: Palette.ink,
                secondaryInk: Palette.secondaryInk, tertiaryInk: Palette.tertiaryInk,
                dimInk: Color(light: 0x707077, dark: 0x87878F),
                accent: accent.accent, onAccent: accent.onAccent, highlight: accent.playingTint,
                track: Palette.hairline, hairline: Palette.hairline)
        case .light:
            let tone = accent.accent.resolved(.light)
            return ReadingPalette(
                theme: self, colorScheme: .light,
                background: Color(hex: 0xFFFFFF), card: Color(hex: 0xF2F2F4), ink: Color(hex: 0x1A1A1C),
                secondaryInk: Color(hex: 0x55555E), tertiaryInk: Color(hex: 0x6B6B74), dimInk: Color(hex: 0x75757C),
                accent: tone, onAccent: Color(hex: 0xFFFFFF), highlight: tone.blended(0.10, over: 0xFFFFFF),
                track: Color(hex: 0xE2E2E6), hairline: Color(hex: 0xE2E2E6))
        case .sepia:
            return ReadingPalette(
                theme: self, colorScheme: .light,
                background: Color(hex: 0xF4ECD8), card: Color(hex: 0xEADFC6), ink: Color(hex: 0x3B2F22),
                secondaryInk: Color(hex: 0x5E4D3A), tertiaryInk: Color(hex: 0x6B5944), dimInk: Color(hex: 0x6F5F4C),
                accent: Color(hex: 0x8A4B1C), onAccent: Color(hex: 0xFFFFFF), highlight: Color(hex: 0xE7D9C1),
                track: Color(hex: 0xDCCDAF), hairline: Color(hex: 0xDCCDAF))
        case .dark:
            let tone = accent.accent.resolved(.dark)
            return ReadingPalette(
                theme: self, colorScheme: .dark,
                background: Color(hex: 0x1C1C1E), card: Color(hex: 0x2C2C2E), ink: Color(hex: 0xECEAE5),
                secondaryInk: Color(hex: 0xA3A3AB), tertiaryInk: Color(hex: 0x96969F), dimInk: Color(hex: 0x8D8D95),
                accent: tone, onAccent: Color(hex: 0x141416), highlight: tone.blended(0.16, over: 0x1C1C1E),
                track: Color(hex: 0x3A3A3E), hairline: Color(hex: 0x3A3A3E))
        case .black:
            let tone = accent.accent.resolved(.dark)
            return ReadingPalette(
                theme: self, colorScheme: .dark,
                background: Color(hex: 0x000000), card: Color(hex: 0x1A1A1C), ink: Color(hex: 0xE4E4E4),
                secondaryInk: Color(hex: 0x9E9EA6), tertiaryInk: Color(hex: 0x8E8E96), dimInk: Color(hex: 0x7C7C84),
                accent: tone, onAccent: Color(hex: 0x141416), highlight: tone.blended(0.18, over: 0x000000),
                track: Color(hex: 0x2E2E32), hairline: Color(hex: 0x2E2E32))
        }
    }
}

/// The reading page's token set, the same for the Reader sheet and Now Playing: what the page,
/// its cards and controls are drawn in. The spoken paragraph sits on `highlight` in full `ink`
/// while the others are `dimInk`; the spoken sentence is underlined in `accent` (one underline
/// colour per theme). `colorScheme` is the theme's own (nil: the app's), set on what the sheet
/// holds so system controls and materials match.
struct ReadingPalette: Equatable {
    let theme: ReadingTheme
    let colorScheme: ColorScheme?
    /// The sheet and the page.
    let background: Color
    /// Field capsules and cards on it: the top bar's pill, the title card, the scrub capsule, the
    /// ⋯ panel.
    let card: Color
    let ink: Color
    let secondaryInk: Color
    let tertiaryInk: Color
    /// The paragraphs not being spoken.
    let dimInk: Color
    /// Links, the play disc and Listen pill, the saved 🔖, progress, the spoken sentence's
    /// underline.
    let accent: Color
    let onAccent: Color
    /// The spoken paragraph's background, ☝︎ while on.
    let highlight: Color
    /// The scrubber's empty track and artwork without an image.
    let track: Color
    /// The edge of a floating panel on the page.
    let hairline: Color

    /// The app's own colours (*Match App*), in the app's colour.
    static var app: ReadingPalette { ReadingTheme.matchApp.palette(accent: AppAppearance.shared.accent) }

    /// Light status bar content and a heavier dim behind the sheet: the theme is dark whatever the
    /// app's appearance.
    var isDark: Bool { colorScheme == .dark }

    /// The underline under the spoken sentence: the theme's accent.
    var underline: Color { accent }
}

extension View {
    /// Drawn on the reading page in `palette` (nil: the app's surface, unchanged): components that
    /// sit on both read `readingPalette`, and system controls and materials take the theme's own
    /// appearance.
    func readingSurface(_ palette: ReadingPalette?) -> some View {
        modifier(ReadingSurface(palette: palette))
    }
}

private struct ReadingSurface: ViewModifier {
    let palette: ReadingPalette?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.readingPalette, palette)
            .environment(\.colorScheme, palette?.colorScheme ?? colorScheme)
    }
}

extension EnvironmentValues {
    /// Inside the Reader sheet or Now Playing (and a ⋯ panel opened from them): the reading page's
    /// colours. nil on the app's surfaces. Components that sit on both read it.
    @Entry var readingPalette: ReadingPalette? = nil
}

/// The reading page's typeface (Settings › Reading, the Aa panel).
enum ReadingFont: String, CaseIterable, Identifiable {
    /// New York.
    case serif
    /// San Francisco.
    case sans
    /// SF Rounded.
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serif: String(localized: "Serif")
        case .sans: String(localized: "Sans Serif")
        case .rounded: String(localized: "Rounded")
        }
    }

    var design: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        }
    }

    /// The CSS `font-family` for the page's body and title.
    var cssFamily: String {
        switch self {
        case .serif: #"ui-serif, "New York", Georgia, serif"#
        case .sans: #"-apple-system, system-ui, sans-serif"#
        case .rounded: #"ui-rounded, -apple-system, system-ui, sans-serif"#
        }
    }
}

/// The reading page's line spacing, as a multiple of the text size.
enum ReadingLineSpacing: String, CaseIterable, Identifiable {
    case compact, normal, relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .normal: String(localized: "Normal")
        case .relaxed: String(localized: "Relaxed")
        }
    }

    var multiple: Double {
        switch self {
        case .compact: 1.4
        case .normal: 1.55
        case .relaxed: 1.75
        }
    }
}

/// How the reading page moves: one long column you scroll, or one page of whole lines at a time
/// that turns (the Reader and Now Playing; `HTMLReadingView+Pages.swift`).
enum ReadingLayout: String, CaseIterable, Identifiable {
    case scroll, pages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: String(localized: "Scroll")
        case .pages: String(localized: "Pages")
        }
    }
}

/// The reading page's text size: a step of the Dynamic Type size (`defaultStep` is 100%), so the
/// system's text size still applies under it.
enum ReadingTextSize {
    static let scales: [Double] = [0.85, 0.92, 1.0, 1.1, 1.2, 1.35, 1.5, 1.65]
    /// The index of 100% in `scales`.
    static let defaultStep = 2
    static var steps: ClosedRange<Int> { 0...(scales.count - 1) }

    static func scale(step: Int) -> Double { scales[steps.clamped(step)] }

    /// "100%".
    static func label(step: Int) -> String { "\(Int((scale(step: step) * 100).rounded()))%" }
}

extension ClosedRange where Bound == Int {
    func clamped(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

extension Color {
    /// One value in light and dark, given as 0xRRGGBB.
    init(hex: UInt32) {
        self.init(light: hex, dark: hex)
    }

    /// The value for one appearance, as a fixed colour.
    func resolved(_ style: UIUserInterfaceStyle) -> Color {
        Color(uiColor: UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }

    /// This colour at `opacity` over the opaque colour `base` (0xRRGGBB), as an opaque colour.
    func blended(_ opacity: Double, over base: UInt32) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func mix(_ c: CGFloat, _ shift: UInt32) -> CGFloat {
            c * opacity + CGFloat((base >> shift) & 0xFF) / 255 * (1 - opacity)
        }
        return Color(uiColor: UIColor(red: mix(r, 16), green: mix(g, 8), blue: mix(b, 0), alpha: 1))
    }
}
