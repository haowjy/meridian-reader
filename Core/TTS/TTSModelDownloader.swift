import Foundation
import Observation

/// Settings-facing setup state for the active on-device engine (preparing / installed / failed).
/// The engines' own libraries download their models (e.g. FluidAudio's `fluidaudio/` cache);
/// this only mirrors progress + errors for the UI. (Formerly also a Chatterbox Nano downloader.)
@MainActor
@Observable
final class TTSModelDownloader {
    enum State: Equatable {
        case idle
        case downloading(fraction: Double, bytesWritten: Int64, totalBytes: Int64)
        case installed
        case failed(String)
    }

    private(set) var state: State = .idle

    func cancel() {
        switch state {
        case .downloading, .failed:
            state = .idle
        case .idle, .installed:
            break
        }
    }

    /// UI hint while the engine's prepare (download + load) is in flight.
    func markPreparing() {
        state = .downloading(fraction: 0, bytesWritten: 0, totalBytes: 0)
    }

    /// UI hint when the engine finished prepare.
    func stateHintInstalled() {
        state = .installed
    }

    /// Clear any hint/failure (after a model delete).
    func resetToIdle() {
        state = .idle
    }

    func markFailed(_ message: String) {
        state = .failed(message)
    }
}
