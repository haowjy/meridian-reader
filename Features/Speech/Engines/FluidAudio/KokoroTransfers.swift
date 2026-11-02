import Foundation
import Observation

/// Every download of a Kokoro voice's files, whoever starts it: a pick in the Voice picker
/// (`FluidAudioProvider.download`), the render queue's host load (`KokoroCPUHost.prepare`), or a
/// render in a voice whose pack isn't on the device (`KokoroCPUHost.prepareVoice`). One transfer per
/// voice; a second asker joins it. The Voice picker shows each on its voice's row and stops it
/// there (`FluidAudioProvider.transfer(of:for:)`, `stopTransfer`), so a download playback started
/// has its ring and ■ too.
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
        let task: Task<Void, Error>
        var observers: [UUID: @Sendable (Double?) -> Void] = [:]
    }

    private var transfers: [String: Transfer] = [:]

    /// `voice`'s transfer in flight, nil when none is.
    func transfer(of voice: String) -> VoiceTransfer? {
        transfers[voice].map { VoiceTransfer(fraction: $0.fraction) }
    }

    /// Stop `voice`'s transfer (the row's ■): everyone waiting on it gets `CancellationError`.
    func stop(_ voice: String) {
        transfers[voice]?.task.cancel()
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

    /// Run `work` as `voice`'s transfer, or join the one in flight. Cancelling the caller stops the
    /// transfer (as it stops the model download it waits on). A transfer stopped while its last
    /// step finished (the model's check ignores a stop) still throws `CancellationError`: the files
    /// stay, but nobody acts on a stopped download.
    func fetch(_ voice: String, progress: (@Sendable (Double?) -> Void)? = nil, work: @escaping Work) async throws {
        let task: Task<Void, Error>
        if let running = transfers[voice] {
            task = running.task
        } else {
            let id = UUID()
            task = Task { @MainActor [weak self] in
                // Gone from the rows the moment it ends, before anyone waiting on it resumes.
                defer { if self?.transfers[voice]?.id == id { self?.transfers[voice] = nil } }
                try await work { fraction in
                    guard var running = self?.transfers[voice], running.id == id else { return }
                    running.fraction = fraction
                    self?.transfers[voice] = running
                    for observer in running.observers.values { observer(fraction) }
                }
                try Task.checkCancellation()
            }
            transfers[voice] = Transfer(id: id, fraction: nil, task: task)
        }
        let token = UUID()
        if let progress { transfers[voice]?.observers[token] = progress }
        defer { transfers[voice]?.observers[token] = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
