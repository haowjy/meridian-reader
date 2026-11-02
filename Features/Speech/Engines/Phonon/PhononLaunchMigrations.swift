import Foundation

/// Builds that downloaded the model kept its zip and the unzipped folder beside the installed copy
/// (about 300 MB). With the bundle in the app nothing reads them: removed whenever they are there.
struct PhononDownloadLeftovers: LaunchMigration {
    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        let fm = FileManager.default
        var freed: Int64 = 0
        for url in PhononModelStore.downloadLeftovers where fm.fileExists(atPath: url.path) {
            freed += FileSizes.allocatedBytes(at: url, fileManager: fm)
            try? fm.removeItem(at: url)
        }
        guard freed > 0 else { return }
        ListenDebugLog.shared.append("Phonon download leftovers removed: \(FileSizes.label(freed))")
        ListenTimingLog.log("phonon_leftovers_removed", ["bytes": freed])
    }
}

/// Phonon's cache voice keys carry the model revision ("phonon.Zoey" → "phonon@1792483937.Zoey",
/// `OnDeviceTraits.cacheRevision`). Audio under the old keys is that revision's: until the bundle
/// shipped in the app, every build downloaded the one release (v0.4.0, the same zip SHA-256 since
/// Phonon was added). Once; engine ids and voice selections don't change. Prepares' `keptVoice`
/// needs no rename: *Keep* was gone before Phonon was added, so none holds a Phonon key.
struct PhononCacheRevision: LaunchMigration {
    static let doneKey = "reader.migration.phononCacheRevision"

    /// The revision every unrevisioned key was rendered by (v0.4.0's `built` stamp). Fixed, not
    /// the current bundle's: a later bundle must not adopt that audio as its own.
    static let legacyRevision = "phonon@1792483937"

    /// A key without a revision, in `legacyRevision`; nil for any other key.
    static func renamed(_ key: String) -> String? {
        key.hasPrefix("phonon.") ? legacyRevision + key.dropFirst("phonon".count) : nil
    }

    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        guard !tts.defaults.bool(forKey: Self.doneKey) else { return }
        let renamed = tts.audioCache.renameVoices(Self.renamed)
        if renamed.complete { tts.defaults.set(true, forKey: Self.doneKey) }
        ListenDebugLog.shared.append("Phonon audio given its model revision: \(renamed.articles) articles")
        ListenTimingLog.log("phonon_cache_revision", ["articles": renamed.articles, "complete": renamed.complete])
        if renamed.articles > 0 { tts.noteBakeMarksChanged() }
    }
}
