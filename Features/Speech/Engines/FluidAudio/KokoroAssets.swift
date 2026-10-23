import FluidAudio
import Foundation

/// Kokoro's files in FluidAudio's English repo directory, shared by both routes: vocab, voice
/// packs, G2P + lexicon, and the Core ML stages (used only by the Core ML route).
enum KokoroAssets {
    /// `Application Support/fluidaudio`: FluidAudio's download cache, every model under it.
    static var fluidAudioDirectory: URL {
        AppDirectories.applicationSupport.appendingPathComponent("fluidaudio", isDirectory: true)
    }

    /// `Application Support/fluidaudio/Models/kokoro-82m-coreml/ANE` (FluidAudio's English repo dir).
    static var repoDirectory: URL {
        fluidAudioDirectory.appendingPathComponent("Models/kokoro-82m-coreml/ANE", isDirectory: true)
    }

    static var repoDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: repoDirectory.path)
    }

    /// Bundled default pack (`Resources/Kokoro/af_heart.bin`, ~0.5 MB). Ships with the app so the
    /// Voice picker never starts empty; copied into the repo dir on first launch.
    static var bundledHeartPackURL: URL? {
        Bundle.main.url(forResource: "af_heart", withExtension: "bin", subdirectory: "Kokoro")
            ?? Bundle.main.url(forResource: "af_heart", withExtension: "bin")
    }

    static func voicePackURL(_ voice: String) -> URL {
        repoDirectory.appendingPathComponent("\(voice).bin")
    }

    static func voicePackInstalled(_ voice: String) -> Bool {
        FileManager.default.fileExists(atPath: voicePackURL(voice).path)
    }

    /// Installed curated packs (ids from `KokoroVoiceCatalog`).
    static func installedCuratedVoiceIDs() -> [String] {
        KokoroVoiceCatalog.curated.map(\.id).filter(voicePackInstalled)
    }

    /// Copy the bundled Heart pack into the repo dir when missing. Returns true when Heart is
    /// present afterwards (already was, or just installed).
    @discardableResult
    static func installBundledHeartIfNeeded(fileManager fm: FileManager = .default) -> Bool {
        let voice = KokoroVoiceCatalog.defaultVoice
        if voicePackInstalled(voice) { return true }
        guard let bundled = bundledHeartPackURL else {
            ListenTimingLog.log("kokoro_voice_bundled_missing", ["voice": voice])
            return false
        }
        do {
            try fm.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
            try fm.copyItem(at: bundled, to: voicePackURL(voice))
            ListenTimingLog.log("kokoro_voice_bundled", ["voice": voice])
            return true
        } catch {
            ListenTimingLog.log("kokoro_voice_bundled_failed", ["voice": voice, "error": "\(error)"])
            return false
        }
    }

    /// Download + convert a voice pack if it isn't on disk yet (FluidAudio fetches
    /// `voices/<id>.json` from the HF repo root and writes `<id>.bin`). Heart prefers the
    /// bundled pack so first launch never needs the network for the default voice.
    static func ensureVoicePack(_ voice: String) async throws {
        if voice == KokoroVoiceCatalog.defaultVoice {
            installBundledHeartIfNeeded()
        }
        guard !voicePackInstalled(voice) else { return }
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
        let t0 = ListenTimingLog.now()
        try await KokoroAneResourceDownloader.ensureVoicePack(voice, repoDirectory: repoDirectory, variant: .english)
        ListenTimingLog.log("kokoro_voice_download", ["voice": voice, "ms": ListenTimingLog.ms(since: t0)])
    }

    /// Remove one voice pack (`.bin`). Does not touch the shared ONNX model or other packs.
    /// Returns bytes freed (0 when the file was already gone).
    @discardableResult
    static func deleteVoicePack(_ voice: String, fileManager fm: FileManager = .default) -> Int64 {
        let url = voicePackURL(voice)
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let bytes = FileSizes.allocatedBytes(at: url, fileManager: fm)
        try? fm.removeItem(at: url)
        ListenTimingLog.log("kokoro_voice_delete", ["voice": voice, "bytes": bytes])
        return bytes
    }

    /// Flat 510×256 fp32 voice pack (`<voice>.bin`).
    static func loadVoicePack(_ voice: String) throws -> [Float] {
        try KokoroAneVoicePack.load(from: voicePackURL(voice)).storage
    }

    /// The Core ML route's 7-stage chain appears to be on disk (cheap existence check).
    static var coreMLStagesLookInstalled: Bool {
        FileManager.default.fileExists(atPath: repoDirectory.appendingPathComponent("KokoroVocoder.mlmodelc").path)
    }

    /// Delete the Core ML stage bundles (keeps vocab, voice packs, G2P + lexicon). Returns bytes freed.
    @discardableResult
    static func deleteCoreMLStages(fileManager fm: FileManager = .default) -> Int64 {
        let dir = repoDirectory
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var freed: Int64 = 0
        for name in items where name.hasSuffix(".mlmodelc") || name.hasSuffix(".mlpackage") {
            let url = dir.appendingPathComponent(name)
            let bytes = FileSizes.allocatedBytes(at: url, fileManager: fm)
            if (try? fm.removeItem(at: url)) != nil { freed += bytes }
        }
        return freed
    }

    /// Remove Kokoro's models and the shared English G2P / lexicon from FluidAudio's cache.
    static func clearCachedModels() {
        let fm = FileManager.default
        let models = AppDirectories.applicationSupport.appendingPathComponent("fluidaudio/Models", isDirectory: true)
        try? fm.removeItem(at: models.appendingPathComponent("kokoro-82m-coreml", isDirectory: true))
        try? fm.removeItem(at: models.appendingPathComponent("kokoro", isDirectory: true))
    }
}
