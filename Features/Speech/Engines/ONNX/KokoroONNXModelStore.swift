import CryptoKit
import Foundation
import Observation

/// Download / verify / delete the Kokoro ONNX fp16 model for Kokoro's main (CPU) route
/// (`KokoroCPUHost.prepare` awaits `ensureInstalled`).
/// `Application Support/CPURoute/kokoro-82m-v1.0-onnx/model_fp16.onnx` (163 MB, excluded from
/// iCloud backup; the folder name predates the route and stays so installed models are found).
/// Foreground `URLSession` download with progress + cancel; SHA-256 verified. One download at a
/// time, shared by everyone who needs the model (every Kokoro voice's transfer, the CPU route
/// benchmark): each is an instance with its own id, waiters and session, so a late callback of a
/// stopped one (URLSession reports a cancel after it) never touches the retry that followed.
@MainActor
@Observable
final class KokoroONNXModelStore {
    static let shared = KokoroONNXModelStore()

    nonisolated static let remoteURL = URL(string: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/onnx/model_fp16.onnx")!
    nonisolated static let expectedBytes: Int64 = 163_234_740
    nonisolated static let sha256 = "ba4527a874b42b21e35f468c10d326fdff3c7fc8cac1f85e9eb6c0dfc35c334a"

    enum State: Equatable {
        case notDownloaded
        case downloading(fraction: Double, written: Int64, total: Int64)
        case verifying
        case installed(bytes: Int64)
        case failed(String)
    }

    private(set) var state: State = .notDownloaded

    /// The download in flight (downloading, then verifying).
    private struct Download {
        let id: UUID
        let task: URLSessionDownloadTask
        let session: URLSession
        /// `ensureInstalled` callers waiting for this download.
        var waiters: [CheckedContinuation<Void, Error>] = []
    }

    private var current: Download?
    private var progressObservers: [UUID: @Sendable (Double) -> Void] = [:]

    /// Cheap existence + size check (no hashing), usable off the main actor.
    nonisolated static var fileLooksInstalled: Bool { installedBytes != nil }

    /// Size of the usable model on disk: the NaN-patched file (preferred) or the verified download.
    nonisolated static var installedBytes: Int64? {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: patchedModelURL.path)[.size] as? NSNumber)?.int64Value,
           size > expectedBytes {
            return size
        }
        let size = (try? fm.attributesOfItem(atPath: modelURL.path)[.size] as? NSNumber)?.int64Value
        return size == expectedBytes ? size : nil
    }

    /// NaN-safe model (`KokoroONNXModelPatch`: atan2(0,0) guard). Written once from the download,
    /// which is then deleted (saves 163 MB).
    nonisolated static var patchedModelURL: URL { KokoroONNXModelPatch.patchedURL(for: modelURL) }

    /// The model file to load: patched if present, else patch the download now (≈1 s, once).
    /// Falls back to the unpatched download if patching fails (the host's NaN guard still applies).
    nonisolated static func ensurePatchedModel() -> (url: URL, patched: Bool, patchedNow: Bool) {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: patchedModelURL.path)[.size] as? NSNumber)?.int64Value,
           size > expectedBytes {
            if fm.fileExists(atPath: modelURL.path) { try? fm.removeItem(at: modelURL) }
            return (patchedModelURL, true, false)
        }
        let t0 = ListenTimingLog.now()
        do {
            let (url, guarded) = try KokoroONNXModelPatch.writePatched(from: modelURL)
            try? fm.removeItem(at: modelURL)
            ListenTimingLog.log("kokoro_onnx_patch", ["ok": true, "guarded": guarded, "ms": ListenTimingLog.ms(since: t0)])
            return (url, true, true)
        } catch {
            ListenTimingLog.log("kokoro_onnx_patch", ["ok": false, "err": error.localizedDescription])
            return (modelURL, false, false)
        }
    }

    /// Download (if needed) and wait until the model is installed, joining the download in
    /// flight. Progress 0…1 while bytes arrive. On cellular or in Low Data Mode it asks first
    /// (`LargeModelDownloadConsent`), a stage a stop ends too. Throws `CancellationError` when the
    /// calling task is cancelled (the download stops, for everyone waiting on it), the prompt is
    /// declined or `cancel()` is called; the download error otherwise.
    func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        refresh()
        if isInstalled { return }
        if current == nil {
            try await LargeModelDownloadConsent.shared.confirmIfNeeded(
                engineName: "Kokoro", bytes: Self.expectedBytes)
            refresh()
            if isInstalled { return }
        }
        // Another caller may have started it while this one was asked.
        let id = current?.id ?? beginDownload()
        let token = UUID()
        if let progress { progressObservers[token] = progress }
        defer { progressObservers[token] = nil }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                guard current?.id == id, !Task.isCancelled else {
                    cont.resume(throwing: CancellationError())
                    return
                }
                current?.waiters.append(cont)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    /// End download `id` for everyone waiting on it; nothing when another has replaced it.
    private func settle(_ id: UUID, _ result: Result<Void, Error>, state next: State) {
        guard let download = current, download.id == id else { return }
        current = nil
        state = next
        for waiter in download.waiters { waiter.resume(with: result) }
    }

    nonisolated static var directory: URL {
        AppDirectories.applicationSupport.appendingPathComponent("CPURoute/kokoro-82m-v1.0-onnx", isDirectory: true)
    }

    nonisolated static var modelURL: URL { directory.appendingPathComponent("model_fp16.onnx") }

    var isInstalled: Bool { if case .installed = state { return true } else { return false } }
    var isBusy: Bool { current != nil }

    init() { refresh() }

    func refresh() {
        guard !isBusy else { return }
        if let size = Self.installedBytes {
            state = .installed(bytes: size)
        } else if case .failed = state {
            // keep the error visible
        } else {
            state = .notDownloaded
        }
    }

    /// The CPU route benchmark's *Download*: the same operation every voice's transfer waits on.
    func download() {
        guard current == nil, !isInstalled else { return }
        Task { try? await ensureInstalled() }
    }

    /// Start a download and return its id.
    private func beginDownload() -> UUID {
        let id = UUID()
        state = .downloading(fraction: 0, written: 0, total: Self.expectedBytes)
        let delegate = DownloadDelegate(
            progress: { [weak self] written, total in
                Task { @MainActor in
                    guard let self, self.current?.id == id, case .downloading = self.state else { return }
                    let t = total > 0 ? total : Self.expectedBytes
                    let f = Double(written) / Double(t)
                    self.state = .downloading(fraction: f, written: written, total: t)
                    for o in self.progressObservers.values { o(f) }
                }
            },
            finished: { [weak self] result in
                Task { @MainActor in self?.finish(id, result) }
            })
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: Self.remoteURL)
        current = Download(id: id, task: task, session: session)
        ListenTimingLog.log("cpubench_model_download", ["op": "start"])
        ListenDebugLog.shared.append("CPU route: model download started")
        task.resume()
        return id
    }

    /// Stop the download in flight (the benchmark's *Cancel*).
    func cancel() {
        if let id = current?.id { cancel(id) }
    }

    /// Stop download `id` while its bytes arrive; its check, once they are in, runs to the end.
    private func cancel(_ id: UUID) {
        guard let download = current, download.id == id, case .downloading = state else { return }
        download.task.cancel()
        download.session.invalidateAndCancel()
        settle(id, .failure(CancellationError()), state: .notDownloaded)
        ListenTimingLog.log("cpubench_model_download", ["op": "cancel"])
        ListenDebugLog.shared.append("CPU route: model download cancelled")
    }

    /// Delete the model (the Voice picker's *Remove* of Kokoro's last voice, the CPU route
    /// benchmark). Nothing while a download is in flight.
    func delete() throws {
        guard !isBusy else { return }
        if FileManager.default.fileExists(atPath: Self.directory.path) {
            try FileManager.default.removeItem(at: Self.directory)
        }
        state = .notDownloaded
        ListenTimingLog.log("cpubench_model_download", ["op": "delete"])
        ListenDebugLog.shared.append("CPU route: model deleted")
    }

    private func finish(_ id: UUID, _ result: Result<URL, Error>) {
        // A stopped download's last callback: its retry (if any) is another download.
        guard let download = current, download.id == id else {
            if case .success(let staged) = result { try? FileManager.default.removeItem(at: staged) }
            return
        }
        download.session.finishTasksAndInvalidate()
        switch result {
        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled {
                settle(id, .failure(CancellationError()), state: .notDownloaded)
                return
            }
            settle(id, .failure(error), state: .failed(error.localizedDescription))
            ListenTimingLog.log("cpubench_model_download", ["op": "fail", "err": error.localizedDescription])
            ListenDebugLog.shared.append("CPU route: download failed: \(error.localizedDescription)")
        case .success(let staged):
            state = .verifying
            Task.detached(priority: .utility) {
                let outcome = Self.verifyAndInstall(staged)
                await MainActor.run {
                    switch outcome {
                    case .success(let bytes):
                        self.settle(id, .success(()), state: .installed(bytes: bytes))
                        ListenTimingLog.log("cpubench_model_download", ["op": "installed", "bytes": bytes])
                        ListenDebugLog.shared.append("CPU route: model installed (\(FileSizes.label(bytes)))")
                    case .failure(let error):
                        self.settle(id, .failure(error), state: .failed(error.localizedDescription))
                        ListenTimingLog.log("cpubench_model_download", ["op": "fail", "err": error.localizedDescription])
                        ListenDebugLog.shared.append("CPU route: verify failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private nonisolated static func verifyAndInstall(_ staged: URL) -> Result<Int64, Error> {
        let fm = FileManager.default
        defer { try? fm.removeItem(at: staged) }
        do {
            let size = (try fm.attributesOfItem(atPath: staged.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size == expectedBytes else {
                ListenTimingLog.log("kokoro_model_bad_download", ["bytes": size, "expected": expectedBytes])
                throw LocalSynthError.engineUnavailable("The download didn’t finish. Try again.")
            }
            let handle = try FileHandle(forReadingFrom: staged)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard hex == sha256 else {
                ListenTimingLog.log("kokoro_model_bad_download", ["sha256": String(hex.prefix(12))])
                throw LocalSynthError.engineUnavailable("The download was damaged. Try again.")
            }
            var dir = directory
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
            try? fm.removeItem(at: modelURL)
            try fm.moveItem(at: staged, to: modelURL)
            return .success(size)
        } catch {
            return .failure(error)
        }
    }
}

/// Session delegate: progress + move the temp file before `didFinishDownloadingTo` returns.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: (Int64, Int64) -> Void
    let finished: (Result<URL, Error>) -> Void
    private var staged: URL?
    private var lastReport: CFAbsoluteTime = 0

    init(progress: @escaping (Int64, Int64) -> Void, finished: @escaping (Result<URL, Error>) -> Void) {
        self.progress = progress
        self.finished = finished
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReport > 0.2 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = now
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            staged = nil
            return
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("cpuroute-\(UUID().uuidString).onnx")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            staged = dest
        } catch {
            staged = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finished(.failure(error))
        } else if let staged {
            finished(.success(staged))
        } else {
            let code = (task.response as? HTTPURLResponse)?.statusCode ?? -1
            finished(.failure(LocalSynthError.engineUnavailable("The download failed (error \(code)). Try again.")))
        }
    }
}
