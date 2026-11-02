import Foundation
import Observation

/// Asks before Kokoro's model download (~163 MB) on cellular or with Low Data Mode on, and says
/// which. Wi‑Fi downloads start without a prompt. *Not Now* stops the download (the voice's row
/// goes back to not downloaded); nothing waits for Wi‑Fi.
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
            }
        }

        var message: String {
            let size = FileSizes.megabytes(bytes)
            return switch caution {
            case .lowDataMode: String(localized: "\(engineName) needs \(size). Low Data Mode is on.")
            case .cellular: String(localized: "\(engineName) needs \(size). You’re not on Wi‑Fi.")
            }
        }
    }

    private(set) var prompt: Prompt?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    /// Returns after the user allows (or when no prompt is needed). Throws `CancellationError`
    /// when they choose Not Now. No-ops under XCTest so unit hosts never hang.
    func confirmIfNeeded(engineName: String, bytes: Int64) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        guard let caution = NetworkPathStatus.shared.largeDownloadCaution else { return }
        let allowed = await request(Prompt(engineName: engineName, bytes: bytes, caution: caution))
        if !allowed { throw CancellationError() }
    }

    func allow() { finish(true) }
    func decline() { finish(false) }
    private func request(_ prompt: Prompt) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            waiters.append(cont)
            if self.prompt == nil { self.prompt = prompt }
        }
    }

    /// Idempotent: alert buttons and `isPresented` set:false can both fire on dismiss.
    private func finish(_ allowed: Bool) {
        guard prompt != nil || !waiters.isEmpty else { return }
        prompt = nil
        let pending = waiters
        waiters = []
        for w in pending { w.resume(returning: allowed) }
    }
}
