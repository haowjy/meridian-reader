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
/// | accent | #0A58CA | #6EA4FF |
/// | onAccent | #FFFFFF | #141416 |
/// | playingTint | #E7EEFB | #1B2A45 |
///
/// The bottom band itself stays on the system `.bar` material (it blurs the page under it);
/// `chrome` is what sits on it and on paper: field capsules, cards, grouped lists.
enum Palette {
    /// Page and sheet background.
    static let paper = Color(light: 0xFBFAF7, dark: 0x141416)
    /// Field capsules, cards, grouped lists, the Now Playing bar.
    static let chrome = Color(light: 0xF3F2EE, dark: 0x1F1F23)
    /// Primary text and glyphs.
    static let ink = Color(light: 0x141416, dark: 0xF2F1EC)
    /// Secondary text: sources, times, counts, captions.
    static let secondaryInk = Color(light: 0x55555E, dark: 0xA1A1AA)
    /// Links, controls, progress, the playing state.
    static let accent = Color(light: 0x0A58CA, dark: 0x6EA4FF)
    /// Text and glyphs on an `accent` fill. White can't reach 4.5:1 on a dark-mode accent light
    /// enough to read on dark paper, so it turns dark there.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x141416)
    /// Background of what is playing: the spoken paragraph, the playing row, a playing pill.
    static let playingTint = Color(light: 0xE7EEFB, dark: 0x1B2A45)
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
