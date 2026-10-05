import SwiftUI
import UIKit

/// The app's colours, each with a light and a dark value (resolved per trait collection, so they
/// follow the system appearance and `preferredColorScheme`). Text pairs keep at least 4.5:1:
///
/// | Token | Light | Dark |
/// |---|---|---|
/// | paper | #FBFAF7 | #141416 |
/// | chrome | #F3F2EE | #1F1F23 |
/// | ink | #141416 | #F2F1EC |
/// | secondaryInk | #55555E | #A1A1AA |
/// | accent | #287060 | #5FB8A0 |
/// | onAccent | #FFFFFF | #141416 |
/// | playingTint | #E6F1ED | #163029 |
///
/// Now Playing is a player: deep jade in both appearances, so its tokens have one value
/// (`player…`, below). Text on it keeps 4.5:1 as well.
///
/// The accent is jade, matching the app icon and Meridian Flow's Ink & Jade palette, one step
/// darker than Flow's jade fill so it also reads as text on `chrome` and `playingTint`.
///
/// The bottom band itself stays on the system `.bar` material (it blurs the page under it);
/// `chrome` is what sits on it and on paper: field capsules, cards, grouped lists.
enum Palette {
    /// Page and sheet background.
    static let paper = Color(light: 0xFBFAF7, dark: 0x141416)
    /// Field capsules, cards, grouped lists.
    static let chrome = Color(light: 0xF3F2EE, dark: 0x1F1F23)
    /// Primary text and glyphs.
    static let ink = Color(light: 0x141416, dark: 0xF2F1EC)
    /// Secondary text: sources, times, counts, captions.
    static let secondaryInk = Color(light: 0x55555E, dark: 0xA1A1AA)
    /// Links, controls, progress, the playing state. The asset catalog's AccentColor carries the
    /// same values, so system controls and `Color.accentColor` match.
    static let accent = Color(light: 0x287060, dark: 0x5FB8A0)
    /// Text and glyphs on an `accent` fill. White can't reach 4.5:1 on a dark-mode accent light
    /// enough to read on dark paper, so it turns dark there.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x141416)
    /// Background of what is playing: the spoken paragraph, the playing row, a playing pill.
    static let playingTint = Color(light: 0xE6F1ED, dark: 0x163029)

    // MARK: The player (Now Playing), the same in light and dark

    /// The player sheet and its reading page.
    static let playerBackground = Color(light: 0x163029, dark: 0x163029)
    /// The player's bottom band (scrubber and transport).
    static let playerChrome = Color(light: 0x10241F, dark: 0x10241F)
    /// Cards and field capsules on the player: the title card, the scrub capsule, the Jump hint.
    static let playerCard = Color(light: 0x1F3D35, dark: 0x1F3D35)
    /// The scrubber's empty track and artwork without an image.
    static let playerTrack = Color(light: 0x2E4C44, dark: 0x2E4C44)
    /// Text and glyphs on the player; the spoken paragraph and its underline.
    static let playerInk = Color(light: 0xF2F1EC, dark: 0xF2F1EC)
    /// The paragraphs not being spoken (lyrics style): about 55% of `playerInk` on
    /// `playerBackground`, the faintest that still reads at 4.5:1.
    static let playerDimInk = Color(light: 0x8E9A94, dark: 0x8E9A94)
    /// Secondary text on the player: "PLAYING FROM", the site and time left, status notes.
    static let playerSecondaryInk = Color(light: 0xA9C6BC, dark: 0xA9C6BC)
    /// The accent on the player (`accent`'s dark value): the big ⏸ / ▶, links, Jump.
    static let playerAccent = Color(light: 0x5FB8A0, dark: 0x5FB8A0)
    /// Glyphs on a `playerAccent` fill.
    static let onPlayerAccent = Color(light: 0x141416, dark: 0x141416)
}

extension EnvironmentValues {
    /// Drawn on the player's palette (inside a `Sheet` with the `.player` look, which also sets a
    /// dark colour scheme for system controls). Components that sit on both read it.
    @Entry var onPlayerPalette = false
}

extension Color {
    /// A colour with a light and a dark value, given as 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
