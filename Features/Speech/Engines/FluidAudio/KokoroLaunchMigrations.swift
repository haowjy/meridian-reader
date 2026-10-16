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

/// A Core ML crash from before the ONNX route existed left Kokoro users on Apple. Bring them back
/// to Kokoro on the stable route, at the article and paragraph of that crash (opened paused).
/// Skipped when this launch already recovered from a Kokoro crash.
struct KokoroONNXMainMigration: LaunchMigration {
    static let doneKey = "reader.tts.kokoro.onnxMainMigration.v1"

    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        let defaults = tts.defaults
        guard !defaults.bool(forKey: Self.doneKey) else { return }
        defaults.set(true, forKey: Self.doneKey)
        guard tts.launchCrash?.engine != .kokoro, tts.selectedEngineID == .apple, tts.engines.supports(.kokoro),
              let last = tts.crashGuard.lastCrash, last.engine == .kokoro else { return }
        let route = KokoroRouteSettings(defaults: tts.defaults)
        route.fastGPURouteEnabled = false
        route.onnxCrashCount = 0
        var target = ListenResumeTarget.forCrash(article: last.articleKey, paragraph: last.paragraph,
                                                 crashAt: last.at, playing: tts.resumePoints.load())
        target?.autoPlay = false
        tts.applyLaunchRecovery(.stay(notice: KokoroCrashRecovery.resumedNotice, resume: target), crashed: .kokoro)
        ListenTimingLog.log("kokoro_onnx_migration", [
            "from": "apple", "resume_key": target?.articleKey.prefix(8) ?? "", "resume_p": target?.paragraph ?? -1,
        ])
    }
}

/// With the Core ML route off, its 7 stages (≈82 MB) are dead weight: the ONNX route needs only
/// the vocab, voice packs and G2P / lexicon files beside them. Deleted at every launch they are
/// found, off the main thread; the Core ML route downloads them again when turned on.
struct KokoroCoreMLStageCleanup: LaunchMigration {
    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        let route = KokoroRouteSettings(defaults: tts.defaults)
        guard !route.fastGPURouteEnabled else { return }
        DispatchQueue.global(qos: .utility).async {
            let freed = KokoroAssets.deleteCoreMLStages()
            guard freed > 0 else { return }
            ListenTimingLog.log("kokoro_coreml_cleanup", ["bytes": freed])
            DispatchQueue.main.async {
                ListenDebugLog.shared.append("Kokoro Core ML stages removed (ONNX route): freed \(FileSizes.label(freed))")
            }
        }
    }
}
