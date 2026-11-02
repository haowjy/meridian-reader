import Foundation
import Observation

/// Every download of a Kokoro voice's files, whoever starts it: a pick in the Voice picker
/// (`FluidAudioProvider.download`), the render queue's host load (`KokoroCPUHost.prepare`), or a
/// render in a voice whose pack isn't on the device (`KokoroCPUHost.prepareVoice`). One transfer per
/// voice; a second asker joins it. The Voice picker shows each on its voice's row and stops it
/// there (`FluidAudioProvider.transfer(of:for:)`, `stopTransfer`), so a download playback started
/// has its ring and ■ too.
///
/// A transfer's whole life is here, whoever started it: its stages (the frontend, the pack, the
/// large-download prompt, the model), its progress, its stop, and how it ended: a failure stays on
/// the voice's row until the next try or its files change (`clearFailure`). The picker keeps only
/// which voice a pick wants (`VoiceDownloads`).
///
/// The model is one file every voice needs: two voices' transfers wait on the same model download
/// (`KokoroONNXModelStore`), and stopping either stops it for both, and for a load waiting on it.
@MainActor
@Observable
final class KokoroTransfers {
    static let shared = KokoroTransfers()

    /// What a transfer runs: the files' downloads, reporting the fraction once the size is known
    /// (nil while it starts or checks).
    typealias Work = @MainActor (_ progress: @escaping @MainActor (Double?) -> Void) async throws -> Void

    private struct Transfer {
        let id: UUID
        var fraction: Double?
        var task: Task<Void, Never>?
        var observers: [UUID: @Sendable (Double?) -> Void] = [:]
        /// Everyone waiting on it, resumed together when it ends (`end`).
        var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    }

    private var transfers: [String: Transfer] = [:]
    /// Voices whose last transfer failed (not a stop).
    private var failures: Set<String> = []

    /// `voice`'s transfer: running, or failed last time; nil when neither.
    func transfer(of voice: String) -> VoiceTransfer? {
        if let running = transfers[voice] { return .running(fraction: running.fraction) }
        return failures.contains(voice) ? .failed : nil
    }

    /// `voice`'s files changed (removed): its row shows what it is now, not an old failure.
    func clearFailure(_ voice: String) {
        failures.remove(voice)
    }

    /// Stop `voice`'s transfer (the row's ■): it ends now for everyone waiting on it
    /// (`CancellationError`), whatever stage it is in, and its work is cancelled.
    func stop(_ voice: String) {
        guard let running = transfers[voice] else { return }
        end(voice, running.id, .failure(CancellationError()))
    }

    /// The files `voice` needs, model included when `model`, are on disk.
    nonisolated static func filesPresent(for voice: String, model: Bool) -> Bool {
        KokoroAneCPUFrontendFiles.present && KokoroAssets.voicePackInstalled(voice)
            && (!model || KokoroONNXModelStore.fileLooksInstalled)
    }

    /// The real downloads: the frontend and the pack (small, so a failure shows at once), then the
    /// model when `model`, asking first on cellular or in Low Data Mode (`LargeModelDownloadConsent`).
    nonisolated static func download(_ voice: String, model: Bool) -> Work {
        { progress in
            progress(nil)
            try await KokoroAneCPUFrontendFiles.download()
            try await KokoroAssets.ensureVoicePack(voice)
            guard model else { return }
            try Task.checkCancellation()
            try await KokoroONNXModelStore.shared.ensureInstalled { fraction in
                // Nil while the finished download is checked.
                Task { @MainActor in progress(fraction < 1 ? fraction : nil) }
            }
        }
    }

    /// A stop (■, *Not Now*, a cancelled waiter), not a failure.
    nonisolated static func isStop(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// Run `work` as `voice`'s transfer, or join the one in flight. The transfer ends once, here
    /// (`end`): when its work finishes or fails, or at a stop, which ends it at once even in a
    /// stage that ignores cancellation (the model's check); a stopped transfer's work finishing
    /// afterwards changes nothing (its files stay, but nobody acts on them). Cancelling a caller
    /// stops the transfer, as it stops the model download it waits on.
    func fetch(_ voice: String, progress: (@Sendable (Double?) -> Void)? = nil, work: @escaping Work) async throws {
        if transfers[voice] == nil { start(voice, work: work) }
        guard let id = transfers[voice]?.id else { throw CancellationError() }
        let token = UUID()
        if let progress { transfers[voice]?.observers[token] = progress }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                guard transfers[voice]?.id == id, !Task.isCancelled else {
                    waiter.resume(throwing: CancellationError())
                    return
                }
                transfers[voice]?.waiters[token] = waiter
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.transfers[voice]?.id == id { self?.stop(voice) }
            }
        }
    }

    private func start(_ voice: String, work: @escaping Work) {
        let id = UUID()
        failures.remove(voice)
        transfers[voice] = Transfer(id: id)
        transfers[voice]?.task = Task { @MainActor [weak self] in
            let result: Result<Void, Error>
            do {
                try await work { fraction in
                    guard var running = self?.transfers[voice], running.id == id else { return }
                    running.fraction = fraction
                    self?.transfers[voice] = running
                    for observer in running.observers.values { observer(fraction) }
                }
                try Task.checkCancellation()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.end(voice, id, result)
        }
    }

    /// End transfer `id` (nothing when it already ended): gone from the rows, a failure (not a
    /// stop) in its place in the same step, then everyone waiting resumes.
    private func end(_ voice: String, _ id: UUID, _ result: Result<Void, Error>) {
        guard let transfer = transfers[voice], transfer.id == id else { return }
        transfers[voice] = nil
        if case .failure(let error) = result {
            transfer.task?.cancel()
            if !Self.isStop(error) {
                failures.insert(voice)
                ListenDebugLog.shared.append("voice download failed \(voice): \(error.localizedDescription)")
            }
        }
        for waiter in transfer.waiters.values { waiter.resume(with: result) }
    }
}
