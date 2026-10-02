import BackgroundTasks
import Foundation

/// Persisted bake jobs for articles that still need audio (`PendingJob`, UserDefaults). Jobs
/// are added on save / open while the local engine is cold and folded into `GlobalSynthQueue`
/// once it warms (`LocalTTSCoordinator.drainPendingIntoQueue`); a finished article drops its job.
///
/// Also registers a `BGProcessingTask`, requested on save. It never renders (see `handle`), so
/// baking happens only while Reader is in the foreground or playing.
@MainActor
final class BackgroundAudioBakeScheduler {
    static let shared = BackgroundAudioBakeScheduler()
    static let taskIdentifier = "com.jimmyyao.Reader.bake-audio"

    private let pendingKey = "reader.tts.pendingBakeJobs"

    private init() {}

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

    /// The processing task runs in the background, where Reader never starts a local model call
    /// (`AppRunState`: no GPU there, and the Core ML CPU paths hit the Kokoro libBNNS crash,
    /// #844). It only re-requests itself and leaves the jobs pending for the foreground queue.
    private func handle(_ task: BGProcessingTask) {
        scheduleProcessingTask()
        ListenTimingLog.log("bg_task_skipped", ["reason": "no_coreml_in_background", "pending": loadPending().count])
        task.setTaskCompleted(success: true)
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
