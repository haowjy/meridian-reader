import Foundation

/// Kokoro's voices in the Voice picker: what choosing one downloads, and what removing one frees.
///
/// A voice is on the device when its pack (`<voice>.bin`, 0.5 MB) and the files every Kokoro
/// voice shares are: the ONNX model (≈163 MB, `KokoroONNXModelStore`) and the frontend's
/// vocab, G2P weights and lexicon. Heart's pack ships in the app (`KokoroHeartPackInstall`), so
/// Heart is on the device whenever the shared files are, and it can't be removed alone: removing
/// it while it is the only voice left removes Kokoro (the model), and every voice downloads again.
extension FluidAudioProvider {
    func downloadSize(of voice: String, for id: SpeechEngineID) -> Int64? {
        guard id == .kokoro else { return nil }
        var bytes: Int64 = 0
        if !modelOnDevice { bytes += KokoroONNXModelStore.expectedBytes }
        if !KokoroAneCPUFrontendFiles.present { bytes += KokoroAneCPUFrontendFiles.downloadBytes }
        if !packOnDevice(voice) { bytes += KokoroAssets.packBytes }
        return bytes > 0 ? bytes : nil
    }

    /// The frontend's files and the pack first (small, so a failure shows at once), then the model, whose
    /// progress is the row's ring. The model download is shared: a render queue load waiting for
    /// it waits for the same transfer (`KokoroONNXModelStore.ensureInstalled`), and it asks first
    /// on cellular or in Low Data Mode (`LargeModelDownloadConsent`).
    func download(_ voice: String, for id: SpeechEngineID,
                  progress: @escaping @MainActor (Double?) -> Void) async throws {
        guard id == .kokoro, downloadSize(of: voice, for: id) != nil else { return }
        #if DEBUG
        if let simulation {
            try await simulation.download(voice, progress: progress)
            return
        }
        #endif
        progress(nil)
        try await KokoroAneCPUFrontendFiles.download()
        try await KokoroAssets.ensureVoicePack(voice)
        try Task.checkCancellation()
        try await KokoroONNXModelStore.shared.ensureInstalled { fraction in
            // Called on the main actor (the store's progress hop); nil while the download is checked.
            Task { @MainActor in progress(fraction < 1 ? fraction : nil) }
        }
    }

    func removal(of voice: String, for id: SpeechEngineID) -> VoiceRemoval? {
        guard id == .kokoro, downloadSize(of: voice, for: id) == nil else { return nil }
        guard voice == KokoroVoiceCatalog.defaultVoice else {
            return VoiceRemoval(bytes: KokoroAssets.packBytes, removesEngine: false)
        }
        // Heart goes only with Kokoro, once it is the last voice on the device.
        let others = Self.kokoroDescriptor.allVoices.map(\.id).filter { $0 != voice && packOnDevice($0) }
        guard others.isEmpty else { return nil }
        return VoiceRemoval(bytes: KokoroONNXModelStore.installedBytes ?? KokoroONNXModelStore.expectedBytes,
                            removesEngine: true)
    }

    func remove(_ voice: String, for id: SpeechEngineID) throws {
        guard let removal = removal(of: voice, for: id) else { return }
        #if DEBUG
        if let simulation {
            simulation.remove(voice, engine: removal.removesEngine)
            return
        }
        #endif
        if removal.removesEngine {
            try KokoroONNXModelStore.shared.delete()
        } else {
            try KokoroAssets.deleteVoicePack(voice)
        }
        ListenTimingLog.log("kokoro_voice_remove", ["voice": voice, "engine": removal.removesEngine,
                                                    "bytes": removal.bytes])
    }

    /// The ONNX model is on disk (a Debug simulation may say it isn't).
    private var modelOnDevice: Bool {
        #if DEBUG
        if let simulation, let shown = simulation.modelOnDevice { return shown }
        #endif
        return KokoroONNXModelStore.fileLooksInstalled
    }

    /// `voice`'s pack is on disk; Heart's always is (it ships in the app).
    private func packOnDevice(_ voice: String) -> Bool {
        if voice == KokoroVoiceCatalog.defaultVoice { return true }
        #if DEBUG
        if let simulation, let shown = simulation.packOnDevice(voice) { return shown }
        #endif
        return KokoroAssets.voicePackInstalled(voice)
    }
}

#if DEBUG
/// `-simulateVoiceDownloads`: Kokoro's downloads and removals in the Voice picker, offline, for
/// probes on the Simulator. Nothing is fetched or deleted; what is on the device is what the
/// launch says, then what the simulated downloads and removals made it. A download spins for a
/// moment (its size unknown), then fills over `seconds`; one of `failing` stops half-way with a
/// network error. `-kokoroNotDownloaded` starts with the model missing.
@MainActor
final class KokoroDownloadSimulation {
    let seconds: Double
    let failing: Set<String>
    /// nil: the files decide.
    private(set) var modelOnDevice: Bool?
    private var packs: [String: Bool] = [:]

    init(seconds: Double, failing: Set<String>, modelMissing: Bool) {
        self.seconds = seconds
        self.failing = failing
        modelOnDevice = modelMissing ? false : nil
    }

    func packOnDevice(_ voice: String) -> Bool? { packs[voice] }

    func download(_ voice: String, progress: @MainActor (Double?) -> Void) async throws {
        progress(nil)
        try await Task.sleep(for: .seconds(1.5))
        let steps = max(1, Int(seconds * 10))
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(100))
            if failing.contains(voice), step == steps / 2 { throw URLError(.networkConnectionLost) }
            progress(Double(step) / Double(steps))
        }
        packs[voice] = true
        modelOnDevice = true
    }

    func remove(_ voice: String, engine: Bool) {
        if engine { modelOnDevice = false } else { packs[voice] = false }
    }
}
#endif
