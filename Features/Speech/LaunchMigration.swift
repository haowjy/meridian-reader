import Foundation

/// A one-time launch step. Each checks and sets its own done flag, so it runs once per install,
/// and it can be deleted once every install has run it. `AppComposition.runLaunchMaintenance`
/// runs the list right after the speech stack is built, before anything renders or plays.
@MainActor
protocol LaunchMigration {
    func runIfNeeded(_ tts: LocalTTSCoordinator)
}

/// A provider retired an engine: delete its cached article audio + index entries (bake marks
/// recompute), orphan CAFs, and its model files. Logged with the bytes freed to the listen debug
/// log and `retired_engine_cleanup` in the timing log.
struct RetiredEngineCleanup: LaunchMigration {
    let engine: RetiredEngine

    func runIfNeeded(_ tts: LocalTTSCoordinator) {
        let defaults = tts.defaults
        guard !defaults.bool(forKey: engine.doneKey) else { return }
        let cache = tts.audioCache.purgeEngine(engine.id.rawValue)
        let modelBytes = engine.deleteFiles()
        defaults.set(true, forKey: engine.doneKey)
        let total = cache.bytes + cache.orphanBytes + modelBytes
        ListenDebugLog.shared.append(
            "retired \(engine.displayName): freed \(FileSizes.label(total)) (models \(FileSizes.label(modelBytes)), "
            + "cached audio \(cache.paragraphs) paragraphs in \(cache.articles) articles \(FileSizes.label(cache.bytes)), "
            + "orphan CAFs \(cache.orphanFiles) \(FileSizes.label(cache.orphanBytes)))")
        ListenTimingLog.log("retired_engine_cleanup", [
            "engine": engine.id.rawValue, "model_bytes": modelBytes,
            "cache_articles": cache.articles, "cache_paragraphs": cache.paragraphs, "cache_bytes": cache.bytes,
            "orphan_files": cache.orphanFiles, "orphan_bytes": cache.orphanBytes, "total_bytes": total,
        ])
        if cache.paragraphs > 0 || cache.orphanFiles > 0 { tts.noteBakeMarksChanged() }
    }
}
