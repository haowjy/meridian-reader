import Foundation
import Observation

/// Asks before Phonon (~131 MB) / Kokoro (~163 MB) model downloads when the path is cellular or
/// Low Data Mode. Apple voices never go through this. Wi‑Fi downloads start without a prompt.
/// Wired once from `RootView`; model stores call `confirmIfNeeded` before starting a transfer.
@MainActor
@Observable
final class LargeModelDownloadConsent {
    static let shared = LargeModelDownloadConsent()

    struct Prompt: Equatable {
        let engineName: String
        let bytes: Int64

        var title: String { String(localized: "Download on Cellular?") }

        var message: String {
            let size = FileSizes.label(bytes)
            return String(localized: "\(engineName) needs about \(size). You're not on Wi‑Fi.")
        }
    }

    private(set) var prompt: Prompt?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    /// Returns after the user allows (or when no prompt is needed). Throws `CancellationError`
    /// when they choose Wait for Wi‑Fi. No-ops under XCTest so unit hosts never hang.
    func confirmIfNeeded(engineName: String, bytes: Int64) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        guard NetworkPathStatus.shared.shouldPromptForLargeDownload else { return }
        let allowed = await request(Prompt(engineName: engineName, bytes: bytes))
        if !allowed { throw CancellationError() }
    }

    func allow() { finish(true) }
    func deferUntilWiFi() { finish(false) }

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
