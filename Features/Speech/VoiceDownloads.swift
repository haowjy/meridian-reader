import Foundation
import Observation

/// The Voice picker's downloads (Settings › Voice, an article's or a book's *Voice*): what each
/// voice still needs, the downloads in flight with their progress, and the ones that failed.
/// Engine facts (sizes, files) come from the voice libraries (`SpeechEngineProvider.downloadSize`,
/// `download`); nothing here names one. Files only: a download loads no engine.
///
/// A pick downloads first and selects after (`pick(_:for:)`): the ✓ stays on the voice before it
/// until the files are there, and only the newest pick of a picker is selected.
@MainActor
@Observable
final class VoiceDownloads {
    /// Where a voice stands in the picker.
    enum Status: Equatable {
        /// Everything it needs is on the device.
        case onDevice
        /// Choosing it downloads `bytes`.
        case notDownloaded(bytes: Int64)
        /// Downloading: `fraction` once the size is known, nil while it starts or checks. `bytes`
        /// stays the row's second line until it finishes.
        case downloading(fraction: Double?, bytes: Int64)
        /// The last download failed (not a cancel); choosing it tries again.
        case failed(bytes: Int64)
    }

    private struct Running {
        var fraction: Double?
        let bytes: Int64
        let task: Task<Bool, Never>
    }

    @ObservationIgnored private let engines: EngineRegistry
    private var running: [VoiceSelection: Running] = [:]
    private var failed: Set<VoiceSelection> = []
    /// Bumped when files may have changed (a download ended, a voice was removed): the files
    /// aren't observable, so rows read it to ask again.
    private(set) var revision: UInt64 = 0
    /// The newest pick of each picker ("default", a `VoiceTarget.id`).
    @ObservationIgnored private var latestPick: [String: VoiceSelection] = [:]

    init(engines: EngineRegistry) {
        self.engines = engines
    }

    func status(of selection: VoiceSelection) -> Status {
        _ = revision
        if let run = running[selection] { return .downloading(fraction: run.fraction, bytes: run.bytes) }
        guard let bytes = engines.downloadSize(of: selection.voice, for: selection.engine) else { return .onDevice }
        return failed.contains(selection) ? .failed(bytes: bytes) : .notDownloaded(bytes: bytes)
    }

    /// A picker chose `selection` (`picker`: "default", a `VoiceTarget.id`): downloads it if it
    /// needs to. True when its files are on the device and it is still that picker's newest pick,
    /// so the caller selects it now; false when the download failed or was stopped, or a later
    /// pick replaced it.
    func pick(_ selection: VoiceSelection, for picker: String) async -> Bool {
        latestPick[picker] = selection
        guard await download(selection), latestPick[picker] == selection else { return false }
        latestPick[picker] = nil
        return true
    }

    /// Download what `selection` needs (joining a download of it in flight). True once it is on
    /// the device. A failure stays on its row until the next try; a cancel isn't a failure.
    func download(_ selection: VoiceSelection) async -> Bool {
        if let run = running[selection] { return await run.task.value }
        guard let bytes = engines.downloadSize(of: selection.voice, for: selection.engine) else { return true }
        failed.remove(selection)
        let engines = engines
        let task = Task { @MainActor [weak self] () -> Bool in
            do {
                try await engines.download(selection.voice, for: selection.engine) { fraction in
                    self?.running[selection]?.fraction = fraction
                }
                return true
            } catch {
                // Stopped (■, the large-download prompt's Not Now): back to not downloaded.
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return false
                }
                self?.failed.insert(selection)
                ListenDebugLog.shared.append("voice download failed \(selection): \(error.localizedDescription)")
                return false
            }
        }
        running[selection] = Running(fraction: nil, bytes: bytes, task: task)
        let done = await task.value
        running[selection] = nil
        revision &+= 1
        return done
    }

    /// The row's ■: stop `selection`'s download. Its row goes back to not downloaded.
    func cancel(_ selection: VoiceSelection) {
        running[selection]?.task.cancel()
    }

    /// What removing `selection` frees; nil when it can't be removed.
    func removal(of selection: VoiceSelection) -> VoiceRemoval? {
        _ = revision
        guard running[selection] == nil else { return nil }
        return engines.removal(of: selection.voice, for: selection.engine)
    }

    /// Files changed outside a download (a removal): rows ask again.
    func filesChanged() {
        failed.removeAll()
        revision &+= 1
    }
}
