import SwiftUI
import UIKit

/// The app's colours, each with a light and a dark value (resolved per trait collection, so they
/// follow the appearance chosen in Settings, `AppAppearance.mode`). Text pairs keep at least 4.5:1:
///
/// | Token | Light | Dark |
/// |---|---|---|
/// | paper | #FBFAF7 | #141416 |
/// | chrome | #F3F2EE | #1F1F23 |
/// | ink | #141416 | #F2F1EC |
/// | secondaryInk | #55555E | #A1A1AA |
/// | tertiaryInk | #6B6B74 | #92929B |
/// | hairline | #E4E2DC | #3A3A40 |
/// | destructive | system red | system red |
/// | caution | #9A5B00 | #F2A93B |
///
/// The accent and what is drawn from it (`accent`, `onAccent`, `playingTint`, `placeholderTile`,
/// `placeholderInk`) are the app's colour, `AccentTheme` (Jade by default: the app icon's, matching
/// Meridian Flow's Ink & Jade palette). They read `AppAppearance.shared`, so a view that draws one
/// redraws when the colour changes. Paper and ink stay neutral in every colour.
///
/// The Reader and Now Playing draw on the reading theme's colours instead (`ReadingPalette`, the
/// `readingPalette` environment value), the same for both.
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
    /// The quieter parts of a secondary line, after its lead: the time left after the site, the
    /// count after a section’s title (`DetailLine`).
    static let tertiaryInk = Color(light: 0x6B6B74, dark: 0x92929B)
    /// Links, controls, progress, the playing state: the app's colour. The root view tints with
    /// it, so system controls match.
    static var accent: Color { AppAppearance.shared.accent.accent }
    /// Text and glyphs on an `accent` fill. White can't reach 4.5:1 on a dark-mode accent light
    /// enough to read on dark paper, so it turns dark there.
    static var onAccent: Color { AppAppearance.shared.accent.onAccent }
    /// A letter tile with no image (a page, folder or book without a cover, a favorite without an
    /// icon): tinted so it reads as artwork on chrome and paper alike; its letter is
    /// `placeholderInk`.
    static var placeholderTile: Color { AppAppearance.shared.accent.placeholderTile }
    /// The letter on `placeholderTile` (≥ 4.5 : 1 on it in both modes).
    static var placeholderInk: Color { AppAppearance.shared.accent.placeholderInk }
    /// Background of what is playing: the playing row, a playing pill, ☝︎ while on.
    static var playingTint: Color { AppAppearance.shared.accent.playingTint }
    /// The edge of a floating panel (the ⋯ panel), so it shows over paper in both appearances.
    static let hairline = Color(light: 0xE4E2DC, dark: 0x3A3A40)
    /// A swipe action that can leave its row in the list (it asks first, as a folder row's
    /// *Delete*; it deletes what the row only shows, as an engine's download; or its change can
    /// fail to save, as a page's *Remove*): the system's red, as a `.destructive` role draws it.
    /// Such an action takes this tint, not the role, which has the list take the row out at once
    /// (`LibraryFolderRow`, `LibraryArticleRow`, the engine rows in Settings).
    static let destructive = Color(uiColor: .systemRed)
    /// A warning glyph (the engine notice's ⚠︎): amber, 3:1 on paper and on the bar material.
    static let caution = Color(light: 0x9A5B00, dark: 0xF2A93B)
    /// The empty part of a ring, a scrubber or a progress line (the reading page's is
    /// `ReadingPalette.track`).
    static let track = secondaryInk.opacity(0.22)
    /// Dims and shadows: the dim behind a sheet or the ⋯ panel, a floating control's shadow.
    static let scrim = Color.black

    // MARK: Washes (translucent fills)

    /// How strong an accent wash is: a tint of the accent behind text in ink (a paragraph
    /// pressed in jump mode). What sits on one is checked for contrast against the wash
    /// composited on what is under it.
    static let washOpacity = 0.15

    /// A control drawn in its own colour that has nothing to do: as faint as the system dims a
    /// disabled toolbar button (‹ / › with no history), so a dimmed 🔖 or ▶ matches them.
    static let disabledOpacity = 0.3
    /// A glyph button under the finger.
    static let pressedOpacity = 0.5
    /// A Library row drawn lighter: a page skipped in playback, a link whose text isn't in.
    static let lighterRowOpacity = 0.6
    /// A Library row's thumbnail while its page downloads, under the jade ↓.
    static let downloadingOpacity = 0.45
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
