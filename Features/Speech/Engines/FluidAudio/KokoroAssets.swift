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

    static func voicePackInstalled(_ voice: String) -> Bool {
        FileManager.default.fileExists(atPath: repoDirectory.appendingPathComponent("\(voice).bin").path)
    }

    /// Download + convert a voice pack if it isn't on disk yet (FluidAudio fetches
    /// `voices/<id>.json` from the HF repo root and writes `<id>.bin`).
    static func ensureVoicePack(_ voice: String) async throws {
        guard !voicePackInstalled(voice) else { return }
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
        let t0 = ListenTimingLog.now()
        try await KokoroAneResourceDownloader.ensureVoicePack(voice, repoDirectory: repoDirectory, variant: .english)
        ListenTimingLog.log("kokoro_voice_download", ["voice": voice, "ms": ListenTimingLog.ms(since: t0)])
    }

    /// Flat 510×256 fp32 voice pack (`<voice>.bin`).
    static func loadVoicePack(_ voice: String) throws -> [Float] {
        try KokoroAneVoicePack.load(from: repoDirectory.appendingPathComponent("\(voice).bin")).storage
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
