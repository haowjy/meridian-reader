import SwiftUI
import XCTest
@testable import Reader

/// The palette's text pairs keep 4.5:1: the app's in both appearances, the player's (Now Playing,
/// one value in both) on each of its backgrounds, and what sits on a translucent fill, composited
/// where the screens use it.
final class ColorContrastTests: XCTestCase {
    func testTextColoursKeepContrastInBothAppearances() {
        let backgrounds: [(String, Color)] = [
            ("paper", Palette.paper), ("chrome", Palette.chrome), ("playingTint", Palette.playingTint),
        ]
        let texts: [(String, Color)] = [
            ("ink", Palette.ink), ("secondaryInk", Palette.secondaryInk), ("accent", Palette.accent),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for (bgName, bg) in backgrounds {
                for (textName, text) in texts {
                    let ratio = Self.contrast(UIColor(text).resolvedColor(with: traits),
                                              UIColor(bg).resolvedColor(with: traits))
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(textName) on \(bgName), \(style.rawValue)")
                }
            }
            let onAccent = Self.contrast(UIColor(Palette.onAccent).resolvedColor(with: traits),
                                         UIColor(Palette.accent).resolvedColor(with: traits))
            XCTAssertGreaterThanOrEqual(onAccent, 4.5, "onAccent on accent, \(style.rawValue)")
        }
    }

    func testPlayerTextKeepsContrastOnThePlayer() {
        let backgrounds: [(String, Color)] = [
            ("playerBackground", Palette.playerBackground), ("playerChrome", Palette.playerChrome),
            ("playerCard", Palette.playerCard),
        ]
        let texts: [(String, Color)] = [
            ("playerInk", Palette.playerInk), ("playerSecondaryInk", Palette.playerSecondaryInk),
            ("playerAccent", Palette.playerAccent),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            func ratio(_ text: Color, on bg: Color) -> CGFloat {
                Self.contrast(UIColor(text).resolvedColor(with: traits), UIColor(bg).resolvedColor(with: traits))
            }
            for (bgName, bg) in backgrounds {
                for (textName, text) in texts {
                    XCTAssertGreaterThanOrEqual(ratio(text, on: bg), 4.5, "\(textName) on \(bgName), \(style.rawValue)")
                }
            }
            // The paragraphs not being spoken, on the reading page.
            XCTAssertGreaterThanOrEqual(ratio(Palette.playerDimInk, on: Palette.playerBackground), 4.5,
                                        "playerDimInk on playerBackground, \(style.rawValue)")
            XCTAssertGreaterThanOrEqual(ratio(Palette.onPlayerAccent, on: Palette.playerAccent), 4.5,
                                        "onPlayerAccent on playerAccent, \(style.rawValue)")
            // The dimmed paragraphs still read as dimmed next to the spoken one.
            XCTAssertGreaterThanOrEqual(ratio(Palette.playerInk, on: Palette.playerDimInk), 2,
                                        "playerInk stands out from playerDimInk, \(style.rawValue)")
        }
    }

    /// Translucent fills, composited on what is under them where the screens use them, against
    /// what sits on them: text at 4.5:1, a glyph at 3:1 (WCAG's non-text contrast).
    func testWhatSitsOnATranslucentFillKeepsContrast() {
        struct Case {
            let name: String
            let fore: Color
            let fill: Color
            let under: Color
            var minimum: CGFloat = 4.5
        }
        let pressedWash = Palette.accent.opacity(Palette.washOpacity)
        let pressedPlayerWash = Palette.playerAccent.opacity(Palette.washOpacity)
        let cases = [
            // The scrub bubble's speed chip (½× / ¼× / Fine): a solid accent fill.
            Case(name: "speed chip", fore: Palette.onPlayerAccent, fill: Palette.playerAccent, under: Palette.playerCard),
            // ☝︎ while on, in the scrub capsule.
            Case(name: "Jump on", fore: Palette.playerAccent, fill: Palette.playerAccentWash,
                 under: Palette.playerCard, minimum: 3),
            // The debug chip, on the player's text.
            Case(name: "debug chip on", fore: Palette.playerInk, fill: Palette.playerAccentWash,
                 under: Palette.playerBackground),
            // A paragraph pressed in jump mode: full ink on the reading page's wash.
            Case(name: "pressed paragraph, player", fore: Palette.playerInk, fill: pressedPlayerWash,
                 under: Palette.playerBackground),
            Case(name: "pressed paragraph, Reader", fore: Palette.ink, fill: pressedWash, under: Palette.paper),
            // The title card's artwork letter, on its tile.
            Case(name: "artwork letter, player", fore: Palette.playerSecondaryInk, fill: Palette.playerTrack,
                 under: Palette.playerCard),
            Case(name: "artwork letter", fore: Palette.secondaryInk, fill: Palette.chrome, under: Palette.paper),
            // The status bar strip above the player: light status bar content on the dim behind
            // the sheet, over the lightest surface there can be (a white web page).
            Case(name: "status bar over the player's dim", fore: .white,
                 fill: .black.opacity(SheetLook.player.maxDim), under: .white),
        ]
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for c in cases {
                let back = Self.composite(UIColor(c.fill).resolvedColor(with: traits),
                                          over: UIColor(c.under).resolvedColor(with: traits))
                let ratio = Self.contrast(UIColor(c.fore).resolvedColor(with: traits), back)
                XCTAssertGreaterThanOrEqual(ratio, c.minimum, "\(c.name), \(style.rawValue): \(ratio)")
            }
        }
    }

    /// The washes are translucent, so the check above composites them.
    func testWashesAreTranslucent() {
        var (r, g, b, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(Palette.playerAccentWash).getRed(&r, green: &g, blue: &b, alpha: &alpha)
        XCTAssertEqual(alpha, Palette.washOpacity, accuracy: 0.01)
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
