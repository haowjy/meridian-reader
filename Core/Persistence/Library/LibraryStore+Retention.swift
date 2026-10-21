import Foundation
import SwiftData

/// C134 retention: three states of an article and its audio.
/// - **Prepared**: saved, and the user chose *Prepare Audio* (a prepare record holds it). Its audio
///   is never cleared automatically.
/// - **Saved**: its text is kept in the Library. Listening renders audio as it goes ("audio from
///   listening"), cleared once the article drops out of Recent.
/// - **Being read**: opened or played without saving. Text and audio are stored as an unsaved
///   article listed in Recent, and both go once it drops out of Recent.
/// Recent is the last `recentLimit` articles started, saved or not (`LibraryQueries.recent`).
extension LibraryStore {
    static let recentLimit = 50

    struct RetentionReport: Equatable {
        var deletedArticles = 0
        var clearedAudio = 0
    }

    /// Applies the retention rule: at launch and whenever Recent changes (an article starts). Audio
    /// listening needs right now (the session, the staged chapter), audio held for unfinished
    /// library work, and prepared audio are never touched. A failed save is rolled back.
    @discardableResult
    func retainRecent() -> RetentionReport {
        var report = RetentionReport()
        let recent = (try? context.fetch(LibraryQueries.recent)) ?? []
        let kept = Set(recent.prefix(Self.recentLimit).compactMap(\.key))
        let lastPlayed = Set(((try? context.fetch(LibraryQueries.lastPlayed)) ?? []).compactMap(\.key))
        func untouchable(_ key: UUID) -> Bool {
            kept.contains(key) || lastPlayed.contains(key) || audio.isPrepared(key) || audio.listeningNeeds(key)
                || audio.audioCache.held.contains(key)
        }
        // Being read and out of Recent (beyond the last 50, or taken out of it): text and audio go.
        let unsaved = (try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate {
            $0.addedAt == nil && !$0.isFavorite && $0.folderID == nil
        }))) ?? []
        for article in unsaved {
            guard let key = article.key, !untouchable(key), article.lastPlayedAt != nil else { continue }
            deleteWithoutSaving(article) // its audio goes through the audio journal, after the save
            report.deletedArticles += 1
        }
        if report.deletedArticles > 0, !commit("retention") {
            rollBack()
            report.deletedArticles = 0
        }
        // Saved (or starred) and out of Recent: only the audio from listening goes.
        for key in audio.audioCache.cachedArticleKeys() where !untouchable(key) {
            guard let article = article(key: key), article.isInLibrary || article.isFavorite else { continue }
            try? audio.clearListenAudio(for: key)
            report.clearedAudio += 1
        }
        if report != RetentionReport() {
            log("retention: deleted \(report.deletedArticles) unsaved articles, cleared listening audio of \(report.clearedAudio)")
            ListenTimingLog.log("retention", ["deleted": report.deletedArticles, "cleared_audio": report.clearedAudio])
        }
        return report
    }
}
