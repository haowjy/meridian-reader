import Foundation

/// Files the app can make again (rendered audio, downloaded models, diagnostics) stay out of the
/// device's iCloud and computer backups: a 10-hour book is about 1.7 GB of audio. The flag on a
/// directory covers everything in it, now and later, so each such directory is created and
/// flagged at launch (`AppComposition.prepareAudioCache`), before anything writes into it.
enum BackupExclusion {
    /// Creates `directory` if needed and keeps it out of backups. False when that failed.
    @discardableResult
    static func exclude(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        var url = directory
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            if isExcluded(url) { return true }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    /// The item at `url` is flagged to stay out of backups (read from disk, not a cached value).
    static func isExcluded(_ url: URL) -> Bool {
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true
    }
}
