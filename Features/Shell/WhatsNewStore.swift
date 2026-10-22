import Foundation

/// Tracks which marketing version's What's New sheet the user has seen, and whether to show it.
///
/// On a fresh install the current version is recorded silently (no sheet). On an upgrade
/// the sheet shows once, then the version is recorded. Reads from `Resources/WhatsNew.json`
/// to decide whether there are notes for the current version.
struct WhatsNewStore {
    static let lastSeenVersionKey = "whatsNew.lastSeenVersion"
    static let storedKeys = [lastSeenVersionKey]

    private let defaults: UserDefaults
    private let currentVersion: String

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") {
        self.defaults = defaults
        self.currentVersion = currentVersion
        recordFreshInstall()
    }

    /// On a fresh install (no stored version at all), silently record the current version so
    /// the user doesn't see What's New on their first launch.
    private func recordFreshInstall() {
        guard defaults.string(forKey: Self.lastSeenVersionKey) == nil else { return }
        defaults.set(currentVersion, forKey: Self.lastSeenVersionKey)
    }

    /// Whether the What's New sheet should show: the current version has notes, and
    /// the user hasn't seen them yet.
    var shouldShow: Bool {
        guard !currentVersion.isEmpty else { return false }
        let lastSeen = defaults.string(forKey: Self.lastSeenVersionKey) ?? ""
        guard lastSeen != currentVersion else { return false }
        return !notes.isEmpty
    }

    /// The user-facing bullets for the current version (empty if none).
    var notes: [String] {
        Self.loadNotes(for: currentVersion)
    }

    /// Mark the current version's What's New as seen.
    func markSeen() {
        defaults.set(currentVersion, forKey: Self.lastSeenVersionKey)
    }

    /// Load the bundled WhatsNew.json and return the bullets for `version`.
    static func loadNotes(for version: String) -> [String] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(WhatsNewFile.self, from: data) else {
            return []
        }
        return root.versions[version] ?? []
    }
}

private struct WhatsNewFile: Decodable {
    let versions: [String: [String]]
}
