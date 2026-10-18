import Foundation
import Observation

/// Developer options and their switches (Settings › Developer, Now Playing's Debug chip and bake
/// overlay, long-press ▶ → Listen debug panel). One store, made in `AppComposition`.
///
/// Developer options are on by default in Debug builds and off in Release. In any build a 2-second
/// long-press on the version row at the bottom of Settings toggles them (haptic + confirmation).
/// A launch argument forces them (`-reader.developerOptions NO|YES`, `-reader.listenDebugEnabled
/// YES`): the argument domain overrides the stored value. A Release build clears a stored "on"
/// once (`releaseResetKey`), so a Debug chip left from an unlock in an older build can't keep
/// showing.
@MainActor
@Observable
final class DeveloperSettings {
    static let enabledKey = "reader.developerOptions"
    /// Set once Release has cleared a stored unlock. The value is a stored key; it can't change.
    static let releaseResetKey = "reader.developerOptions.releaseReset.navJ"
    static let listenDebugKey = "reader.listenDebugEnabled"
    /// Long-press on the version row that toggles developer options.
    static let unlockPressSeconds: Double = 2

    @ObservationIgnored private let defaults: UserDefaults

    /// Developer options on. Off turns off what they show and do.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                showBakeDebugOverlay = false
                fakeExtractionFailure = false
            }
        }
    }

    /// Now Playing shows a Debug chip that toggles the bake overlay. Stored.
    var listenDebugEnabled: Bool {
        didSet {
            defaults.set(listenDebugEnabled, forKey: Self.listenDebugKey)
            if !listenDebugEnabled { showBakeDebugOverlay = false }
        }
    }

    /// The bake overlay above Now Playing's controls (the Debug chip's toggle).
    var showBakeDebugOverlay = false

    /// Every extraction fails until the app quits (`DeveloperSwitchedExtractor`).
    var fakeExtractionFailure = false

    /// Now Playing's Debug chip: Listen debug on, with developer options on.
    var showsListenDebugUI: Bool { isEnabled && listenDebugEnabled }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        #if DEBUG
        let enabledWithoutChoice = true
        #else
        let enabledWithoutChoice = false
        if defaults.object(forKey: Self.releaseResetKey) == nil {
            defaults.set(false, forKey: Self.enabledKey)
            defaults.set(true, forKey: Self.releaseResetKey)
        }
        #endif
        // `bool(forKey:)` also reads launch-argument strings ("NO" / "YES").
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil
            ? enabledWithoutChoice : defaults.bool(forKey: Self.enabledKey)
        listenDebugEnabled = defaults.bool(forKey: Self.listenDebugKey)
    }

    /// "Version 1.0 (1)" from the bundle.
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}

/// The app's extractor (`AppComposition.extractor`): `base`, except that every extraction fails
/// while *Fake Extraction Failure* is on: the browser's Reader and Save, Follow's preview and
/// chapters, a download's page.
struct DeveloperSwitchedExtractor: ArticleExtracting {
    let base: any ArticleExtracting
    let developer: DeveloperSettings

    func extract(from context: ExtractionContext) async throws -> ExtractedArticle {
        if await developer.fakeExtractionFailure {
            throw ExtractionError.unavailable(reason: "This page doesn’t look like an article (Fake Extraction Failure).")
        }
        return try await base.extract(from: context)
    }
}
