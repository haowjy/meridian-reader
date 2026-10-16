import SwiftUI
import XCTest
@testable import MeridianReader

/// The colour tokens keep their contrast: the app's text on its surfaces in every colour
/// (`AccentTheme`) and both appearances, each reading theme's (`ReadingPalette`) on its page and
/// cards, and what sits on a translucent fill, composited where the screens use it.
final class ColorContrastTests: XCTestCase {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    func testNeutralTextKeepsContrastInBothAppearances() {
        let backgrounds: [(String, Color)] = [("paper", Palette.paper), ("chrome", Palette.chrome)]
        let texts: [(String, Color)] = [
            ("ink", Palette.ink), ("secondaryInk", Palette.secondaryInk), ("tertiaryInk", Palette.tertiaryInk),
        ]
        for style in Self.styles {
            for (bgName, bg) in backgrounds {
                for (textName, text) in texts {
                    XCTAssertGreaterThanOrEqual(Self.ratio(text, bg, style), 4.5, "\(textName) on \(bgName), \(style.rawValue)")
                }
                // The engine notice's ⚠︎: a glyph, 3:1.
                XCTAssertGreaterThanOrEqual(Self.ratio(Palette.caution, bg, style), 3, "caution on \(bgName), \(style.rawValue)")
            }
        }
    }

    /// Every app colour: its accent reads as text on paper, chrome and its playing tint, ink
    /// reads on the tint, the glyph on an accent fill reads, and a letter tile's letter reads.
    func testEveryAppColourKeepsContrastInBothAppearances() {
        for theme in AccentTheme.allCases {
            for style in Self.styles {
                let name = "\(theme.rawValue), \(style.rawValue)"
                for (bgName, bg) in [("paper", Palette.paper), ("chrome", Palette.chrome), ("playingTint", theme.playingTint)] {
                    XCTAssertGreaterThanOrEqual(Self.ratio(theme.accent, bg, style), 4.5, "accent on \(bgName), \(name)")
                }
                XCTAssertGreaterThanOrEqual(Self.ratio(Palette.ink, theme.playingTint, style), 4.5, "ink on playingTint, \(name)")
                XCTAssertGreaterThanOrEqual(Self.ratio(theme.onAccent, theme.accent, style), 4.5, "onAccent on accent, \(name)")
                XCTAssertGreaterThanOrEqual(Self.ratio(theme.placeholderInk, theme.placeholderTile, style), 4.5,
                                            "placeholderInk on placeholderTile, \(name)")
            }
        }
    }

    /// `Palette`'s accent tokens are the chosen colour's.
    func testPaletteFollowsTheChosenColour() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let chosen = AppAppearance.shared.accent
        XCTAssertEqual(Self.hex(Palette.accent, traits), Self.hex(chosen.accent, traits))
        XCTAssertEqual(Self.hex(Palette.playingTint, traits), Self.hex(chosen.playingTint, traits))
        XCTAssertEqual(Self.hex(Palette.placeholderTile, traits), Self.hex(chosen.placeholderTile, traits))
    }

    /// Every reading theme, in every app colour and both app appearances: the text on its page and
    /// cards, the dimmed paragraphs on the page, the spoken paragraph on its highlight, the
    /// underline (its accent) on the highlight, and a glyph on an accent fill.
    func testEveryReadingThemeKeepsContrast() {
        for accent in AccentTheme.allCases {
            for theme in ReadingTheme.allCases {
                let p = theme.palette(accent: accent)
                for style in Self.styles {
                    let name = "\(theme.rawValue) in \(accent.rawValue), app \(style.rawValue)"
                    for (bgName, bg) in [("background", p.background), ("card", p.card)] {
                        for (textName, text) in [("ink", p.ink), ("secondaryInk", p.secondaryInk),
                                                 ("tertiaryInk", p.tertiaryInk), ("accent", p.accent)] {
                            XCTAssertGreaterThanOrEqual(Self.ratio(text, bg, style), 4.5, "\(textName) on \(bgName), \(name)")
                        }
                    }
                    XCTAssertGreaterThanOrEqual(Self.ratio(p.dimInk, p.background, style), 4.5, "dimInk on background, \(name)")
                    XCTAssertGreaterThanOrEqual(Self.ratio(p.ink, p.dimInk, style), 2, "ink stands out from dimInk, \(name)")
                    XCTAssertGreaterThanOrEqual(Self.ratio(p.ink, p.highlight, style), 4.5, "ink on highlight, \(name)")
                    XCTAssertGreaterThanOrEqual(Self.ratio(p.underline, p.highlight, style), 3, "underline on highlight, \(name)")
                    XCTAssertGreaterThanOrEqual(Self.ratio(p.onAccent, p.accent, style), 4.5, "onAccent on accent, \(name)")
                    XCTAssertGreaterThanOrEqual(Self.ratio(p.secondaryInk, p.track, style), 3, "artwork letter on track, \(name)")
                }
            }
        }
    }

    /// One underline colour per theme: its accent, in the Reader and Now Playing alike.
    func testEachReadingThemeUnderlinesInItsAccent() {
        for theme in ReadingTheme.allCases {
            let p = theme.palette(accent: .harbor)
            for style in Self.styles {
                let traits = UITraitCollection(userInterfaceStyle: style)
                XCTAssertEqual(Self.hex(p.underline, traits), Self.hex(p.accent, traits), theme.rawValue)
            }
        }
        // Sepia keeps its own accent; the others take the app's colour.
        let traits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(Self.hex(ReadingTheme.sepia.palette(accent: .plum).accent, traits),
                       Self.hex(ReadingTheme.sepia.palette(accent: .jade).accent, traits))
        XCTAssertEqual(Self.hex(ReadingTheme.light.palette(accent: .plum).accent, traits),
                       Self.hex(AccentTheme.plum.accent, traits))
    }

    /// Light and Sepia are light whatever the app's appearance; Dark and Black dark; Match App
    /// follows the app.
    func testReadingThemesCarryTheirOwnAppearance() {
        XCTAssertNil(ReadingTheme.matchApp.palette(accent: .jade).colorScheme)
        XCTAssertEqual(ReadingTheme.light.palette(accent: .jade).colorScheme, .light)
        XCTAssertEqual(ReadingTheme.sepia.palette(accent: .jade).colorScheme, .light)
        XCTAssertTrue(ReadingTheme.dark.palette(accent: .jade).isDark)
        XCTAssertTrue(ReadingTheme.black.palette(accent: .jade).isDark)
        let traits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(Self.hex(ReadingTheme.black.palette(accent: .jade).background, traits), "#000000")
    }

    /// Translucent fills, composited on what is under them where the screens use them, against
    /// what sits on them: text at 4.5:1.
    func testWhatSitsOnATranslucentFillKeepsContrast() {
        for theme in ReadingTheme.allCases {
            let p = theme.palette(accent: .jade)
            for style in Self.styles {
                let traits = UITraitCollection(userInterfaceStyle: style)
                // A paragraph pressed in jump mode: full ink on the accent wash over the page.
                let wash = Self.composite(UIColor(p.accent.opacity(Palette.washOpacity)).resolvedColor(with: traits),
                                          over: UIColor(p.background).resolvedColor(with: traits))
                XCTAssertGreaterThanOrEqual(Self.contrast(UIColor(p.ink).resolvedColor(with: traits), wash), 4.5,
                                            "pressed paragraph, \(theme.rawValue), \(style.rawValue)")
            }
        }
        // The status bar strip above a dark reading theme: light status bar content on the dim
        // behind the sheet, over the lightest surface there can be (a white web page).
        let dim = Sheet<EmptyView, EmptyView>.maxDim(ReadingTheme.dark.palette(accent: .jade))
        let strip = Self.composite(UIColor.black.withAlphaComponent(dim), over: .white)
        XCTAssertGreaterThanOrEqual(Self.contrast(.white, strip), 4.5, "status bar over a dark theme's dim")
    }

    private static func ratio(_ fore: Color, _ back: Color, _ style: UIUserInterfaceStyle) -> CGFloat {
        let traits = UITraitCollection(userInterfaceStyle: style)
        return contrast(UIColor(fore).resolvedColor(with: traits), UIColor(back).resolvedColor(with: traits))
    }

    private static func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        ReadingStyle.hex(color, traits)
    }

    /// `fill` (with its alpha) over the opaque `under`.
    private static func composite(_ fill: UIColor, over under: UIColor) -> UIColor {
        var (fr, fg, fb, fa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (ur, ug, ub, ua): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        fill.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        under.getRed(&ur, green: &ug, blue: &ub, alpha: &ua)
        func mix(_ f: CGFloat, _ u: CGFloat) -> CGFloat { f * fa + u * (1 - fa) }
        return UIColor(red: mix(fr, ur), green: mix(fg, ug), blue: mix(fb, ub), alpha: 1)
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
