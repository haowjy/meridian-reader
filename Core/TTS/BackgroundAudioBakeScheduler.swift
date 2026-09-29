import BackgroundTasks
import Foundation

/// Best-effort background bake for saved articles that still need audio.
///
/// Honesty: iOS does **not** grant unbounded Core ML time. `BGProcessingTask` may
/// run for a short window when the device is idle/charging — or never. We register,
/// request on save, process what we can, and re-request. Foreground /
/// active-session bake in `LocalTTSCoordinator` remains the reliable path.
@MainActor
final class BackgroundAudioBakeScheduler {
    static let shared = BackgroundAudioBakeScheduler()
    static let taskIdentifier = "com.jimmyyao.Reader.bake-audio"

    private let pendingKey = "reader.tts.pendingBakeJobs"
    weak var coordinator: LocalTTSCoordinator?

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await BackgroundAudioBakeScheduler.shared.handle(processing)
            }
        }
    }

    struct PendingJob: Codable, Equatable {
        var articleID: UUID
        var paragraphs: [String]
        var rate: Float
        var voiceID: String
        var priorityStart: Int
        var fillGapsFromTopAfterPriority: Bool
    }

    func enqueuePending(
        articleID: UUID,
        paragraphs: [String],
        rate: Float,
        voiceID: String,
        plan: BakePriorityPlan
    ) {
        var jobs = loadPending()
        jobs.removeAll { $0.articleID == articleID }
        jobs.append(
            PendingJob(
                articleID: articleID,
                paragraphs: paragraphs,
                rate: rate,
                voiceID: voiceID,
                priorityStart: plan.priorityStart,
                fillGapsFromTopAfterPriority: plan.fillGapsFromTopAfterPriority
            )
        )
        savePending(jobs)
    }

    func removePending(articleID: UUID) {
        var jobs = loadPending()
        jobs.removeAll { $0.articleID == articleID }
        savePending(jobs)
    }

    /// Pending jobs waiting for local-engine readiness or a BG processing window.
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

    private func handle(_ task: BGProcessingTask) async {
        // Always ask again so leftovers can continue later.
        scheduleProcessingTask()

        // Processing tasks run in the background, where Reader never starts a Core ML call (no
        // GPU; the CPU paths hit the Kokoro libBNNS crash, #844). Keep the jobs pending for the
        // foreground queue instead of spinning until expiry.
        guard AppRunState.shared.allowsLocalModelCalls else {
            ListenTimingLog.log("bg_task_skipped", ["reason": "no_coreml_in_background", "pending": loadPending().count])
            task.setTaskCompleted(success: true)
            return
        }

        let jobs = loadPending()
        guard let job = jobs.first, let coordinator else {
            task.setTaskCompleted(success: true)
            return
        }

        var expired = false
        task.expirationHandler = {
            expired = true
            Task { @MainActor in
                coordinator.cancelBake(for: job.articleID)
            }
        }

        if job.priorityStart <= 0, !job.fillGapsFromTopAfterPriority {
            coordinator.startBakeIfNeeded(
                articleID: job.articleID,
                paragraphs: job.paragraphs,
                rate: job.rate,
                voiceID: job.voiceID
            )
        } else {
            coordinator.prioritizeBake(
                articleID: job.articleID,
                from: job.priorityStart,
                paragraphs: job.paragraphs,
                rate: job.rate,
                voiceID: job.voiceID
            )
        }

        while !expired, coordinator.bakePlans[job.articleID] != nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        task.setTaskCompleted(success: !expired)
    }

    private func loadPending() -> [PendingJob] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([PendingJob].self, from: data)) ?? []
    }

    private func savePending(_ jobs: [PendingJob]) {
        if let data = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }
}
