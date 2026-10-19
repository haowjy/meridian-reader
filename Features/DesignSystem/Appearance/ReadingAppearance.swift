import SwiftUI

/// How pages read (Settings › Reading and the Aa panel on the Reader and Now Playing): the reading
/// theme, the typeface, the text size step, the line spacing and Scroll or Pages, stored in
/// UserDefaults (`reading.theme`, `reading.font`, `reading.textSize`, `reading.lineSpacing`,
/// `reading.layout`). Both editors bind
/// to the one store in the environment, so they never disagree, and the page follows it live.
@Observable
final class ReadingAppearance {
    static let themeKey = "reading.theme"
    static let fontKey = "reading.font"
    static let textSizeKey = "reading.textSize"
    static let lineSpacingKey = "reading.lineSpacing"
    static let layoutKey = "reading.layout"
    static let storedKeys = [themeKey, fontKey, textSizeKey, lineSpacingKey, layoutKey]

    @ObservationIgnored private let defaults: UserDefaults

    var theme: ReadingTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) }
    }

    var font: ReadingFont {
        didSet { defaults.set(font.rawValue, forKey: Self.fontKey) }
    }

    /// An index into `ReadingTextSize.scales`; `ReadingTextSize.defaultStep` is 100%.
    var textSizeStep: Int {
        didSet {
            // Observation's setter calls this again for the clamped value, which then stores it.
            let clamped = ReadingTextSize.steps.clamped(textSizeStep)
            guard clamped == textSizeStep else { textSizeStep = clamped; return }
            defaults.set(textSizeStep, forKey: Self.textSizeKey)
        }
    }

    var lineSpacing: ReadingLineSpacing {
        didSet { defaults.set(lineSpacing.rawValue, forKey: Self.lineSpacingKey) }
    }

    var layout: ReadingLayout {
        didSet { defaults.set(layout.rawValue, forKey: Self.layoutKey) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        theme = defaults.string(forKey: Self.themeKey).flatMap(ReadingTheme.init(rawValue:)) ?? .matchApp
        font = defaults.string(forKey: Self.fontKey).flatMap(ReadingFont.init(rawValue:)) ?? .serif
        textSizeStep = defaults.object(forKey: Self.textSizeKey) == nil
            ? ReadingTextSize.defaultStep
            : ReadingTextSize.steps.clamped(defaults.integer(forKey: Self.textSizeKey))
        lineSpacing = defaults.string(forKey: Self.lineSpacingKey).flatMap(ReadingLineSpacing.init(rawValue:)) ?? .normal
        layout = defaults.string(forKey: Self.layoutKey).flatMap(ReadingLayout.init(rawValue:)) ?? .scroll
    }

    var textScale: Double { ReadingTextSize.scale(step: textSizeStep) }
    var canShrinkText: Bool { textSizeStep > ReadingTextSize.steps.lowerBound }
    var canGrowText: Bool { textSizeStep < ReadingTextSize.steps.upperBound }

    func shrinkText() { if canShrinkText { textSizeStep -= 1 } }
    func growText() { if canGrowText { textSizeStep += 1 } }

    /// The page's colours in the app's colour `accent`.
    func palette(accent: AccentTheme) -> ReadingPalette { theme.palette(accent: accent) }

    /// Everything back to how a new install reads.
    func reset() {
        theme = .matchApp
        font = .serif
        textSizeStep = ReadingTextSize.defaultStep
        lineSpacing = .normal
        layout = .scroll
    }
}

extension EnvironmentValues {
    /// The app's reading appearance store (`AppComposition`); a default one for previews.
    @Entry var readingAppearance = ReadingAppearance(defaults: .standard)
}
