import Foundation
import Observation

/// The Voice picker's downloads (Settings › Voice, an article's or a book's *Voice*): what each
/// voice still needs, read from its library (`SpeechEngineProvider.downloadSize`, `transfer`), and
/// which voice each picker's newest pick wants. A transfer's life (its progress, stop and failure)
/// is its library's, one per voice whoever started it, so a download playback started shows and
/// fails on its row the same way; nothing here records one. Nothing here names a library. Files
/// only: a download loads no engine.
///
/// A pick downloads first and selects after (`pick(_:for:)`): the ✓ stays on the voice before it
/// until the files are there, and only the newest pick of a picker is selected.
@MainActor
@Observable
final class VoiceDownloads {
    /// Where a voice stands in the picker.
    enum Status: Equatable {
        /// Everything it needs is on the device, its own files taking `bytes` (nil: unknown).
        case onDevice(bytes: Int64?)
        /// Choosing it downloads `bytes`.
        case notDownloaded(bytes: Int64)
        /// Downloading: `fraction` once the size is known, nil while it starts, asks or checks.
        /// `bytes` stays the row's second line until it finishes.
        case downloading(fraction: Double?, bytes: Int64)
        /// The last download failed (not a stop); choosing it tries again.
        case failed(bytes: Int64)
    }

    @ObservationIgnored private let engines: EngineRegistry
    /// Bumped when files changed outside a transfer (a removal): the files aren't observable, so
    /// rows read it to ask again.
    private(set) var revision: UInt64 = 0
    /// The newest pick of each picker ("default", a `VoiceTarget.id`).
    @ObservationIgnored private var latestPick: [String: VoiceSelection] = [:]

    init(engines: EngineRegistry) {
        self.engines = engines
    }

    func status(of selection: VoiceSelection) -> Status {
        _ = revision
        let size = engines.downloadSize(of: selection.voice, for: selection.engine)
        switch engines.transfer(of: selection.voice, for: selection.engine) {
        case .running(let fraction): return .downloading(fraction: fraction, bytes: size ?? 0)
        case .failed: if let size { return .failed(bytes: size) }
        case nil: break
        }
        guard let size else {
            return .onDevice(bytes: engines.installedSize(of: selection.voice, for: selection.engine))
        }
        return .notDownloaded(bytes: size)
    }

    /// A picker chose `selection` (`picker`: "default", a `VoiceTarget.id`), the voice it already
    /// has included (which supersedes a pick still downloading): downloads it if it needs to. True
    /// when its files are on the device and it is still that picker's newest pick, so the caller
    /// selects it now; false when the download failed or was stopped (■ forgets the pick), or a
    /// later pick replaced it.
    func pick(_ selection: VoiceSelection, for picker: String) async -> Bool {
        latestPick[picker] = selection
        guard await download(selection), latestPick[picker] == selection else { return false }
        latestPick[picker] = nil
        return true
    }

    /// Download what `selection` needs, as its library's transfer (joining one in flight). True
    /// once it is on the device; false when it failed (its row says so) or was stopped.
    func download(_ selection: VoiceSelection) async -> Bool {
        do {
            try await engines.download(selection.voice, for: selection.engine)
            return engines.downloadSize(of: selection.voice, for: selection.engine) == nil
        } catch {
            return false
        }
    }

    /// The row's ■: stop `selection`'s transfer, whoever started it (playback waiting on it stops
    /// waiting), and forget every pick of it, so nothing selects it. Its row goes back to not
    /// downloaded.
    func cancel(_ selection: VoiceSelection) {
        for (picker, pick) in latestPick where pick == selection { latestPick[picker] = nil }
        engines.stopTransfer(of: selection.voice, for: selection.engine)
    }

    /// What removing `selection` frees; nil when it can't be removed (not on the device, or its
    /// transfer is running).
    func removal(of selection: VoiceSelection) -> VoiceRemoval? {
        _ = revision
        if case .running = engines.transfer(of: selection.voice, for: selection.engine) { return nil }
        return engines.removal(of: selection.voice, for: selection.engine)
    }

    /// Files changed outside a transfer (a removal): rows ask again.
    func filesChanged() {
        revision &+= 1
    }
}
