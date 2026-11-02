import Foundation
import Observation

/// Asks before Kokoro's model download (~163 MB) on cellular or with Low Data Mode on, and says
/// which. Wi‑Fi downloads start without a prompt. *Not Now* stops the download (the voice's row
/// goes back to not downloaded); nothing waits for Wi‑Fi. Asking is a stage of the transfer: a
/// stop (■, a cancelled load) while it waits for the network's answer or for the prompt ends that
/// wait at once, and the prompt goes when nobody is left waiting on it.
/// Wired once from `RootView`; model stores call `confirmIfNeeded` before starting a transfer.
@MainActor
@Observable
final class LargeModelDownloadConsent {
    static let shared = LargeModelDownloadConsent()

    struct Prompt: Equatable {
        let engineName: String
        let bytes: Int64
        let caution: NetworkPathStatus.LargeDownloadCaution

        var title: String {
            switch caution {
            case .lowDataMode: String(localized: "Download in Low Data Mode?")
            case .cellular: String(localized: "Download on Cellular?")
            case .unknown: String(localized: "Download \(engineName)?")
            }
        }

        var message: String {
            let size = FileSizes.megabytes(bytes)
            return switch caution {
            case .lowDataMode: String(localized: "\(engineName) needs \(size). Low Data Mode is on.")
            case .cellular: String(localized: "\(engineName) needs \(size). You’re not on Wi‑Fi.")
            case .unknown: String(localized: "\(engineName) needs \(size). The network didn’t say whether it’s Wi‑Fi.")
            }
        }
    }

    private(set) var prompt: Prompt?
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    /// Returns after the user allows (or when no prompt is needed). Throws `CancellationError`
    /// when they choose Not Now or the calling task is cancelled. No-ops under XCTest so unit
    /// hosts never hang.
    func confirmIfNeeded(engineName: String, bytes: Int64) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        let caution = await NetworkPathStatus.shared.largeDownloadCaution()
        try Task.checkCancellation()
        guard let caution else { return }
        let allowed = await request(Prompt(engineName: engineName, bytes: bytes, caution: caution))
        if !allowed || Task.isCancelled { throw CancellationError() }
    }

    func allow() { finish(true) }
    func decline() { finish(false) }

    /// One answer for everyone waiting; a cancelled waiter leaves with false, and takes the prompt
    /// with it when it was the last.
    private func request(_ prompt: Prompt) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    cont.resume(returning: false)
                    return
                }
                waiters[id] = cont
                if self.prompt == nil { self.prompt = prompt }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.leave(id) }
        }
    }

    private func leave(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        if waiters.isEmpty { prompt = nil }
        waiter.resume(returning: false)
    }

    /// Idempotent: alert buttons and `isPresented` set:false can both fire on dismiss.
    private func finish(_ allowed: Bool) {
        guard prompt != nil || !waiters.isEmpty else { return }
        prompt = nil
        let pending = waiters.values
        waiters = [:]
        for w in pending { w.resume(returning: allowed) }
    }
}
