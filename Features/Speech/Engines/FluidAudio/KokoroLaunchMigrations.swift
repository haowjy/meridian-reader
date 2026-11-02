import Foundation

/// Delete saved Kokoro audio older than `version` (all articles; bake marks recompute). v2: audio
/// rendered before the ONNX NaN fix can contain full-scale pops + seconds of silence, has ≈0.8 s
/// of dead air at every chunk join, and follows a chunk plan that cut mid-phrase.
struct KokoroAudioCachePurge: LaunchMigration {
    static let version = 2
    static let versionKey = "reader.tts.kokoro.audioCacheVersion"

    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        let defaults = tts.defaults
        guard defaults.integer(forKey: Self.versionKey) < Self.version else { return }
        let r = tts.audioCache.purgeEngine(SpeechEngineID.kokoro.rawValue)
        // Audio held for unfinished library work is purged by a later launch.
        if r.held == 0 { defaults.set(Self.version, forKey: Self.versionKey) }
        ListenTimingLog.log("kokoro_audio_cache_purge", [
            "version": Self.version, "articles": r.articles, "paragraphs": r.paragraphs,
            "bytes": r.bytes, "orphan_files": r.orphanFiles, "orphan_bytes": r.orphanBytes, "held": r.held,
        ])
        ListenDebugLog.shared.append(
            "Kokoro audio cache v\(Self.version): removed \(r.paragraphs) saved paragraphs in \(r.articles) articles "
            + "(\(FileSizes.label(r.bytes + r.orphanBytes))); they re-render with the NaN fix + new chunking")
        if r.paragraphs > 0 || r.orphanFiles > 0 { tts.noteBakeMarksChanged() }
    }
}

/// Kokoro renders only on its ONNX CPU route. An older build's Core ML route left its 7 stages
/// (≈82 MB) beside the vocab, voice packs and G2P / lexicon files the ONNX route still reads, and
/// stored its on/off setting. At every launch: the setting goes, and the stages are deleted off
/// the main thread whenever they are found.
struct KokoroCoreMLStageCleanup: LaunchMigration {
    static let fastGPURouteKey = "reader.tts.kokoro.fastGPURoute"

    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        tts.defaults.removeObject(forKey: Self.fastGPURouteKey)
        DispatchQueue.global(qos: .utility).async {
            let freed = KokoroAssets.deleteCoreMLStages()
            guard freed > 0 else { return }
            ListenTimingLog.log("kokoro_coreml_cleanup", ["bytes": freed])
            DispatchQueue.main.async {
                ListenDebugLog.shared.append("Kokoro Core ML stages removed: freed \(FileSizes.label(freed))")
            }
        }
    }
}

/// Copy the bundled Heart voice pack into FluidAudio's cache when missing so the Voice picker
/// never starts empty. Idempotent; runs every launch (cheap existence check).
struct KokoroHeartPackInstall: LaunchMigration {
    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        guard tts.engines.supports(.kokoro) else { return }
        KokoroAssets.installBundledHeartIfNeeded()
    }
}
