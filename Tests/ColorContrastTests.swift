import SwiftUI
import XCTest
@testable import Reader

/// The palette's text pairs keep 4.5:1: the app's in both appearances, the player's (Now Playing,
/// one value in both) on each of its backgrounds.
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
