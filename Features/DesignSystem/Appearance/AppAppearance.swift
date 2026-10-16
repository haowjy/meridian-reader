import SwiftUI
import UIKit

/// The app's theme (Settings › Appearance): its appearance and its colour, stored in UserDefaults
/// (`appearance.mode`, `appearance.accent`). One store for the app (`shared`), built before the
/// first view: `Palette`'s accent tokens read `accent` from it, so a view drawing them redraws when
/// it changes (Observation tracks the read wherever it happens in a body). The appearance is set on
/// every window of the app (`applyToWindows`): sheets, alerts and menus follow it too.
@Observable
final class AppAppearance {
    static let modeKey = "appearance.mode"
    static let accentKey = "appearance.accent"

    /// The app's store. Tests make their own with a scratch `UserDefaults`.
    static let shared = AppAppearance(defaults: .standard)

    @ObservationIgnored private let defaults: UserDefaults

    var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            applyToWindows()
        }
    }

    var accent: AccentTheme {
        didSet {
            defaults.set(accent.rawValue, forKey: Self.accentKey)
            applyToWindows()
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // A launch argument (`-appearance.mode dark`) reads through the argument domain.
        mode = defaults.string(forKey: Self.modeKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        accent = defaults.string(forKey: Self.accentKey).flatMap(AccentTheme.init(rawValue:)) ?? .jade
    }

    /// Sets the appearance and the colour (UIKit's tint: alerts, system menus) on every window of
    /// the app's scenes. The root view calls it once its window is up; each change calls it again.
    func applyToWindows() {
        let style = mode.interfaceStyle
        let tint = UIColor(accent.accent)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                if window.overrideUserInterfaceStyle != style { window.overrideUserInterfaceStyle = style }
                window.tintColor = tint
            }
        }
    }
}
