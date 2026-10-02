import BackgroundTasks
import Foundation

/// Persisted bake jobs for articles that still need audio (`PendingJob`). Jobs are added on save
/// / open while the local engine is cold and folded into `GlobalSynthQueue` once it warms
/// (`LocalTTSCoordinator.drainPendingIntoQueue`); a finished article drops its job.
///
/// Jobs carry the article's paragraphs, so they live in a small JSON file in Application Support,
/// not in UserDefaults (whose plist is loaded whole at every launch). Older builds kept them under
/// `reader.tts.pendingBakeJobs` in UserDefaults; the first load moves them to the file.
///
/// Also registers a `BGProcessingTask`. The coordinator requests it only while the active route
/// may render in the background (Kokoro ONNX); its handler doesn't render yet — background
/// bake-ahead is limited to the article that is playing — so it logs and completes, and the jobs
/// stay pending for the foreground queue.
@MainActor
final class BackgroundAudioBakeScheduler {
    static let shared = BackgroundAudioBakeScheduler()
    static let taskIdentifier = "com.jimmyyao.Reader.bake-audio"

    private static let legacyDefaultsKey = "reader.tts.pendingBakeJobs"
    private let storeURL: URL
    private let defaults: UserDefaults

    nonisolated static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PendingBakeJobs.json")
    }

    /// `storeURL` / `defaults` are injectable for tests.
    init(storeURL: URL = BackgroundAudioBakeScheduler.defaultStoreURL, defaults: UserDefaults = .standard) {
        self.storeURL = storeURL
        self.defaults = defaults
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                BackgroundAudioBakeScheduler.shared.handle(processing)
            }
        }
    }

    struct PendingJob: Codable, Equatable {
        var articleID: UUID
        var paragraphs: [String]
        var voiceID: String
        var priorityStart: Int
        var fillGapsFromTopAfterPriority: Bool
    }

    func enqueuePending(
        articleID: UUID,
        paragraphs: [String],
        voiceID: String,
        plan: BakePriorityPlan
    ) {
        var jobs = loadPending()
        jobs.removeAll { $0.articleID == articleID }
        jobs.append(
            PendingJob(
                articleID: articleID,
                paragraphs: paragraphs,
                voiceID: voiceID,
                priorityStart: plan.priorityStart,
                fillGapsFromTopAfterPriority: plan.fillGapsFromTopAfterPriority
            )
        )
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

    func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = true
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BGBake] submit failed: \(error.localizedDescription)")
        }
    }

    /// Nothing renders here (see the type comment). Not re-requested: the next save on a route
    /// that renders in the background asks again.
    private func handle(_ task: BGProcessingTask) {
        ListenTimingLog.log("bg_task_skipped", ["reason": "bake_ahead_foreground_only", "pending": loadPending().count])
        task.setTaskCompleted(success: true)
    }

    private func loadPending() -> [PendingJob] {
        if let data = defaults.data(forKey: Self.legacyDefaultsKey) {
            // Move jobs written by older builds out of UserDefaults (once).
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
