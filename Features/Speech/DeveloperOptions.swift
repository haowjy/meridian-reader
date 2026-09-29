import Foundation

/// Developer options (Nav I / J): the ⋯ menu's Debug rows, Settings → Listen → Listen debug, the
/// listen bar's Debug chip / bake overlay and long-press-play → Listen debug panel.
///
/// Off by default in Release (hidden from normal use), on by default in Debug builds. In any build
/// a 2-second long-press on the version row at the bottom of Voice settings toggles it (haptic +
/// confirmation). UI tests force it with the launch argument `-reader.developerOptions NO|YES`
/// (the argument domain overrides the stored value).
///
/// Nav J: the first Release launch after this update clears a previously stored "on" so a Debug
/// pill left over from an earlier unlock (or a bad default) cannot keep showing. Long-press the
/// version row again to turn developer options back on.
enum DeveloperOptions {
    static let defaultsKey = "reader.developerOptions"
    /// Set once after forcing developer options off on a Release upgrade (Nav J).
    static let releaseResetKey = "reader.developerOptions.releaseReset.navJ"
    /// Long-press on the version row that toggles developer options.
    static let unlockPressSeconds: Double = 2

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// The stored choice wins; with none, developer options follow the build (Debug on, Release off).
    static func resolve(stored: Bool?, isDebugBuild: Bool) -> Bool { stored ?? isDebugBuild }

    static func load(_ defaults: UserDefaults = .standard) -> Bool {
        clearStaleReleaseUnlockIfNeeded(defaults)
        // `bool(forKey:)` also reads launch-argument strings ("NO" / "YES").
        let stored: Bool? = defaults.object(forKey: defaultsKey) == nil ? nil : defaults.bool(forKey: defaultsKey)
        return resolve(stored: stored, isDebugBuild: isDebugBuild)
    }

    /// Release only: one-time clear of a stored unlock so the Debug pill cannot stick on after
    /// upgrading to Nav J. Launch arguments still win for UI tests.
    static func clearStaleReleaseUnlockIfNeeded(_ defaults: UserDefaults = .standard,
                                                isDebugBuild: Bool = DeveloperOptions.isDebugBuild) {
        guard !isDebugBuild else { return }
        guard defaults.object(forKey: releaseResetKey) == nil else { return }
        defaults.set(false, forKey: defaultsKey)
        defaults.set(true, forKey: releaseResetKey)
    }

    /// "Version 1.0 (1)" from the bundle.
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}
