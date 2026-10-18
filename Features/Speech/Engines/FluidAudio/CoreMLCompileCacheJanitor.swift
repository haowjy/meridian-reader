import Foundation

/// Core ML's E5RT compiled-model cache (`Library/Caches/<bundle id>/com.apple.e5rt.e5bundlecache/
/// <OS build>/<model hash>/…`) gets fresh compiled bundles for every model each time the app binary
/// changes (every install / update) and never evicts the stale ones: a development iPhone held
/// 16.7 GB of them after a day of installs (hundreds of MB per compiled model).
///
/// Once per install, delete bundle dirs whose newest file predates this launch (the first launch of
/// the install). Core ML recompiles anything it still needs — which it does after a binary change anyway (the one slow
/// first Kokoro load after an install), so this costs nothing extra. One of FluidAudio's launch steps.
struct CoreMLCompileCacheJanitor {
    struct Report: Sendable {
        var bundlesRemoved = 0
        var bytesFreed: Int64 = 0
        var bundlesKept = 0
    }

    static let defaultsKey = "reader.coreml.e5janitor.installID"

    static var cacheRoot: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return caches.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
    }

    /// Changes with every install: iOS puts each installed binary in a fresh
    /// `/…/Bundle/Application/<UUID>/MeridianReader.app` container. (Bundle file dates are no use: on
    /// device they read as the epoch, so a date stamp matched the "never ran" default of 0.)
    static var installID: String {
        Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent
    }

    /// Once per install, on a GCD utility queue (not Swift concurrency: at launch the cooperative
    /// pool can be busy with model loading). `cutoff` should be taken at process launch, before any
    /// model loads, so bundles compiled by this launch are newer and survive.
    /// `completion` gets nil when it already ran for this install.
    static func runOncePerInstall(cutoff: Date = Date(), defaults: UserDefaults = .standard,
                                  completion: @escaping @Sendable (Report?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(runOncePerInstallSync(cutoff: cutoff, defaults: defaults))
        }
    }

    static func runOncePerInstallSync(cutoff: Date, installID: String = installID,
                                      defaults: UserDefaults = .standard) -> Report? {
        guard let root = cacheRoot, !installID.isEmpty else { return nil }
        guard defaults.string(forKey: defaultsKey) != installID else { return nil }
        let report = sweep(root: root, olderThan: cutoff)
        defaults.set(installID, forKey: defaultsKey)
        return report
    }

    /// Delete `<root>/<os build>/<bundle>` dirs whose newest file is older than `cutoff`.
    static func sweep(root: URL, olderThan cutoff: Date, fileManager fm: FileManager = .default) -> Report {
        var report = Report()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let osDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return report }
        for osDir in osDirs {
            guard let bundles = try? fm.contentsOfDirectory(at: osDir, includingPropertiesForKeys: keys) else { continue }
            for bundle in bundles {
                if newestModification(bundle, fm: fm) < cutoff {
                    let bytes = FileSizes.allocatedBytes(at: bundle, fileManager: fm)
                    if (try? fm.removeItem(at: bundle)) != nil {
                        report.bundlesRemoved += 1
                        report.bytesFreed += bytes
                    }
                } else {
                    report.bundlesKept += 1
                }
            }
            if (try? fm.contentsOfDirectory(atPath: osDir.path))?.isEmpty == true {
                try? fm.removeItem(at: osDir)
            }
        }
        return report
    }

    private static func newestModification(_ url: URL, fm: FileManager) -> Date {
        var newest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let u as URL in e {
                if let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   d > newest { newest = d }
            }
        }
        return newest
    }
}

extension CoreMLCompileCacheJanitor: LaunchMigration {
    /// Logs `coreml_cache_prune` when it removed anything.
    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        Self.runOncePerInstall { report in
            guard let r = report else { return }
            ListenTimingLog.log("coreml_cache_prune", [
                "removed": r.bundlesRemoved, "kept": r.bundlesKept, "bytes": r.bytesFreed,
            ])
            DispatchQueue.main.async {
                ListenDebugLog.shared.append(
                    "Core ML compile cache: removed \(r.bundlesRemoved) stale bundles, freed \(FileSizes.label(r.bytesFreed)) (kept \(r.bundlesKept))")
            }
        }
    }
}
