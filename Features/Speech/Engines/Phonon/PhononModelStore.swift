import Foundation
import PhononTTS

/// The Phonon 31m English Core ML bundle ships inside the app (`PhononBundle`, the ptts v0.4.0
/// release, put in place at build time by `tools/fetch-phonon-bundle.sh`): every voice, nothing
/// to download. Core ML compiles a model beside its package, so Phonon can't load from the
/// read-only app bundle: the first load of a process copies it into Application Support, and the
/// compiled models stay beside the copy.
///
/// Under `Application Support/PhononTTS`:
/// - `models/`: the installed copy `Phonon.load` uses (`PhononModels.defaultDirectory`)
/// - `models.staging/`: a copy in progress, swapped in only once complete
/// - `phonon-31m-en-coreml.zip`, `bundle/`, `bundle.partial/`: left by builds that downloaded the
///   model; nothing reads them (`PhononDownloadLeftovers` removes them at launch)
enum PhononModelStore {
    /// `built` in the shipped bundle's `bundle.json`: which export renders Phonon's audio. It is the
    /// cache revision (`PhononProvider.descriptor`), so a different bundle files its audio under
    /// new cache voice keys and audio of this one stops counting as prepared. Change it with the
    /// bundle (`tools/fetch-phonon-bundle.sh`).
    nonisolated static let bundleBuilt = 1_792_483_937

    nonisolated static var rootDirectory: URL {
        AppDirectories.applicationSupport.appendingPathComponent("PhononTTS", isDirectory: true)
    }
    nonisolated static var modelsDirectory: URL { PhononModels.defaultDirectory }
    nonisolated private static var stagingDirectory: URL {
        rootDirectory.appendingPathComponent("models.staging", isDirectory: true)
    }
    /// What builds that downloaded the model left; obsolete with the bundle in the app.
    nonisolated static var downloadLeftovers: [URL] {
        ["phonon-31m-en-coreml.zip", "bundle", "bundle.partial"].map { rootDirectory.appendingPathComponent($0) }
    }

    /// The bundle in the app; nil only in a build packaged without it (`tools/fetch-phonon-bundle.sh`).
    nonisolated static var shippedBundle: URL? {
        Bundle.main.url(forResource: "PhononBundle", withExtension: nil)
    }

    /// The copy in progress or done this process. One per process, before the first `Phonon.load`,
    /// so a copy never replaces files under a loaded model.
    @MainActor private static var install: Task<Void, Error>?

    /// `models/` holds the shipped bundle: kept when it already holds that export (a copy or an
    /// earlier download of it), else copied. Off the main actor; a failure is tried again next time.
    @MainActor static func ensureInstalled() async throws {
        let task = install ?? Task.detached(priority: .userInitiated) { try installShippedBundle() }
        install = task
        do {
            try await task.value
        } catch {
            if install == task { install = nil }
            throw error
        }
    }

    /// Remove the installed copy (debug: model delete). The next load copies the bundle again.
    @MainActor static func delete() {
        install = nil
        let fm = FileManager.default
        for url in [modelsDirectory, stagingDirectory] + downloadLeftovers { try? fm.removeItem(at: url) }
    }

    nonisolated private static func installShippedBundle() throws {
        let t0 = ListenTimingLog.now()
        guard let source = shippedBundle else {
            assertionFailure("PhononBundle is missing from the app: run tools/fetch-phonon-bundle.sh")
            ListenTimingLog.log("phonon_install_failed", ["err": "no PhononBundle in the app"])
            throw LocalSynthError.engineUnavailable("The voice is missing from this build")
        }
        let shipped = built(at: source)
        if shipped != bundleBuilt {
            assertionFailure("PhononBundle built \(shipped ?? -1), PhononModelStore.bundleBuilt \(bundleBuilt)")
            ListenTimingLog.log("phonon_bundle_mismatch", ["shipped": shipped ?? -1, "expected": bundleBuilt])
        }
        if PhononModels.isInstalled(at: modelsDirectory), built(at: modelsDirectory) == shipped {
            ListenTimingLog.log("phonon_install", ["copied": false, "ms": ListenTimingLog.ms(since: t0)])
            return
        }
        let fm = FileManager.default
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fm.removeItem(at: stagingDirectory)
        try fm.copyItem(at: source, to: stagingDirectory)
        try? fm.removeItem(at: modelsDirectory)
        try fm.moveItem(at: stagingDirectory, to: modelsDirectory)
        BackupExclusion.exclude(modelsDirectory)
        ListenTimingLog.log("phonon_install", ["copied": true, "ms": ListenTimingLog.ms(since: t0)])
    }

    /// The `built` stamp of the bundle in `directory`.
    nonisolated private static func built(at directory: URL) -> Int? {
        struct Stamp: Decodable { let built: Int }
        return (try? Data(contentsOf: directory.appendingPathComponent("bundle.json")))
            .flatMap { try? JSONDecoder().decode(Stamp.self, from: $0).built }
    }
}
