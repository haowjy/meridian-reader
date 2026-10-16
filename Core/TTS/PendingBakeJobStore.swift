import Foundation

/// Persisted bake jobs for articles that still need audio (`PendingJob`). Jobs are added on save
/// / open while the local engine is cold and folded into `GlobalSynthQueue` once it warms
/// (`LocalTTSCoordinator.drainPendingIntoQueue`); a finished article drops its job.
///
/// Jobs carry the article's paragraphs, so they live in a small JSON file in Application Support,
/// not in UserDefaults (whose plist is loaded whole at every launch). Jobs still under the legacy
/// `reader.tts.pendingBakeJobs` UserDefaults key move to the file on the first load.
@MainActor
final class PendingBakeJobStore {
    static let shared = PendingBakeJobStore()

    private static let legacyDefaultsKey = "reader.tts.pendingBakeJobs"
    private let storeURL: URL
    private let defaults: UserDefaults

    nonisolated static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PendingBakeJobs.json")
    }

    /// `storeURL` / `defaults` are injectable for tests.
    init(storeURL: URL = PendingBakeJobStore.defaultStoreURL, defaults: UserDefaults = .standard) {
        self.storeURL = storeURL
        self.defaults = defaults
    }

    /// A job renders in whatever voice is selected when it runs, so it stores no voice. Files
    /// written with the `voiceID` and `fillGapsFromTopAfterPriority` fields still decode: the
    /// decoder ignores keys it doesn't know.
    struct PendingJob: Codable, Equatable {
        var articleID: UUID
        var paragraphs: [String]
        var priorityStart: Int
    }

    /// `priorityStart`: the paragraph rendering starts from (then the rest to the end, then the
    /// paragraphs above it).
    func enqueuePending(articleID: UUID, paragraphs: [String], priorityStart: Int) {
        var jobs = loadPending()
        jobs.removeAll { $0.articleID == articleID }
        jobs.append(PendingJob(articleID: articleID, paragraphs: paragraphs, priorityStart: priorityStart))
        savePending(jobs)
    }

    func removePending(articleID: UUID) {
        var jobs = loadPending()
        guard jobs.contains(where: { $0.articleID == articleID }) else { return }
        jobs.removeAll { $0.articleID == articleID }
        savePending(jobs)
    }

    /// Pending jobs waiting for local-engine readiness.
    func pendingJobs() -> [PendingJob] { loadPending() }

    private func loadPending() -> [PendingJob] {
        if let data = defaults.data(forKey: Self.legacyDefaultsKey) {
            // Move legacy UserDefaults jobs to the file (once).
            let legacy = (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? []
            savePending(legacy)
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
            return legacy
        }
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? []
    }

    private func savePending(_ jobs: [PendingJob]) {
        guard !jobs.isEmpty else {
            try? FileManager.default.removeItem(at: storeURL)
            return
        }
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }
}
