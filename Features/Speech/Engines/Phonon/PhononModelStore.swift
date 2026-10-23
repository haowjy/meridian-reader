import CryptoKit
import Foundation
import PhononTTS
import ZIPFoundation

/// Download / verify / unzip / install the Phonon 31m English Core ML bundle.
/// Release asset: `phonon-31m-en-coreml.zip` (~131 MB). Not GGUF q8 — iOS uses Core ML; this PR
/// forces `computeUnit: .cpu` for the CPU probe Jimmy asked for.
///
/// Layout under Application Support:
/// - `PhononTTS/phonon-31m-en-coreml.zip` — verified download
/// - `PhononTTS/bundle/` — unzipped folder (source for `PhononModels.install`)
/// - `PhononTTS/models/` — writable install `Phonon.load` uses (`PhononModels.defaultDirectory`)
@MainActor
final class PhononModelStore {
    static let shared = PhononModelStore()

    nonisolated static let remoteURL = URL(
        string: "https://github.com/gradium-ai/xn-ptts/releases/download/v0.4.0/phonon-31m-en-coreml.zip")!
    /// Uncompressed listing size is larger; zip size on the v0.4.0 release.
    nonisolated static let expectedZipBytes: Int64 = 137_096_081
    nonisolated static let zipSHA256 = "10f3a99fd39256db44f826267ef21d78cca959b16c0554926344c09fde27b436"
    /// Top-level folder inside the zip.
    nonisolated static let zipRootName = "phonon-31m-en-coreml"

    nonisolated static var rootDirectory: URL {
        AppDirectories.applicationSupport.appendingPathComponent("PhononTTS", isDirectory: true)
    }
    nonisolated static var zipURL: URL { rootDirectory.appendingPathComponent("phonon-31m-en-coreml.zip") }
    nonisolated static var extractedBundleURL: URL {
        rootDirectory.appendingPathComponent("bundle", isDirectory: true)
    }
    nonisolated static var modelsDirectory: URL { PhononModels.defaultDirectory }

    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var progressObservers: [UUID: @Sendable (Double) -> Void] = [:]
    private var isBusy = false

    /// Bundle.json present and PhononModels reports installed.
    nonisolated static var filesLookInstalled: Bool {
        PhononModels.isInstalled(at: modelsDirectory)
    }

    func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if Self.filesLookInstalled {
            progress?(1)
            return
        }
        let token = UUID()
        if let progress { progressObservers[token] = progress }
        defer { progressObservers.removeValue(forKey: token) }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            waiters.append(cont)
            if !isBusy {
                isBusy = true
                startDownload()
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        failWaiters(CancellationError())
    }

    func delete() {
        cancel()
        let fm = FileManager.default
        for url in [Self.zipURL, Self.extractedBundleURL, Self.modelsDirectory, Self.rootDirectory] {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Download

    private func startDownload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.rootDirectory, withIntermediateDirectories: true)
        BackupExclusion.exclude(Self.rootDirectory)

        // Reuse a verified zip already on disk.
        if fm.fileExists(atPath: Self.zipURL.path),
           (try? fm.attributesOfItem(atPath: Self.zipURL.path)[.size] as? NSNumber)?.int64Value == Self.expectedZipBytes,
           (try? Self.sha256(of: Self.zipURL)) == Self.zipSHA256 {
            Task { await self.finishFromZip() }
            return
        }

        let delegate = DownloadDelegate(
            progress: { [weak self] written, total in
                let expected = total > 0 ? total : Self.expectedZipBytes
                let f = min(0.85, Double(written) / Double(expected))
                Task { @MainActor in self?.broadcast(f) }
            },
            finished: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let staged):
                        do {
                            try self.verifyAndKeepZip(staged)
                            await self.finishFromZip()
                        } catch {
                            self.failWaiters(error)
                        }
                    case .failure(let error):
                        self.failWaiters(error)
                    }
                }
            })
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: Self.remoteURL)
        self.task = task
        broadcast(0.01)
        task.resume()
    }

    private func verifyAndKeepZip(_ staged: URL) throws {
        let fm = FileManager.default
        let size = (try fm.attributesOfItem(atPath: staged.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size == Self.expectedZipBytes else {
            try? fm.removeItem(at: staged)
            throw LocalSynthError.engineUnavailable("Phonon zip size mismatch (\(size))")
        }
        let hex = try Self.sha256(of: staged)
        guard hex == Self.zipSHA256 else {
            try? fm.removeItem(at: staged)
            throw LocalSynthError.engineUnavailable("Phonon zip SHA-256 mismatch (\(hex.prefix(12))…)")
        }
        try fm.createDirectory(at: Self.rootDirectory, withIntermediateDirectories: true)
        try? fm.removeItem(at: Self.zipURL)
        try fm.moveItem(at: staged, to: Self.zipURL)
    }

    private func finishFromZip() async {
        do {
            broadcast(0.88)
            try Self.unzipBundle()
            broadcast(0.95)
            _ = try PhononModels.install(bundled: Self.extractedBundleURL, to: Self.modelsDirectory)
            broadcast(1)
            succeedWaiters()
        } catch {
            failWaiters(error)
        }
    }

    nonisolated private static func unzipBundle() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let staging = rootDirectory.appendingPathComponent("bundle.partial", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw LocalSynthError.engineUnavailable("Could not open Phonon zip")
        }
        for entry in archive {
            let dest = staging.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: dest)
            }
        }
        let extracted = staging.appendingPathComponent(zipRootName, isDirectory: true)
        guard fm.fileExists(atPath: extracted.appendingPathComponent("bundle.json").path) else {
            throw LocalSynthError.engineUnavailable("Phonon zip missing bundle.json")
        }
        try? fm.removeItem(at: extractedBundleURL)
        try fm.moveItem(at: extracted, to: extractedBundleURL)
        try? fm.removeItem(at: staging)
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func broadcast(_ fraction: Double) {
        for o in progressObservers.values { o(fraction) }
    }

    private func succeedWaiters() {
        isBusy = false
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        let pending = waiters
        waiters = []
        for w in pending { w.resume() }
    }

    private func failWaiters(_ error: Error) {
        isBusy = false
        task = nil
        session?.invalidateAndCancel()
        session = nil
        let pending = waiters
        waiters = []
        for w in pending { w.resume(throwing: error) }
    }
}

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
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("phonon-\(UUID().uuidString).zip")
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
            finished(.failure(LocalSynthError.engineUnavailable("Phonon download failed (HTTP \(code))")))
        }
    }
}
