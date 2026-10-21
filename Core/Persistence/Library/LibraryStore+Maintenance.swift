import Foundation
import SwiftData

/// Launch maintenance on the library (`migrateLegacy` and `dedupe` live in their own files), the
/// trim of finished chapters' audio, "audio ready", and crash-resume lookup.
extension LibraryStore {
    // MARK: - Paragraph layout

    struct LayoutMigrationReport: Equatable {
        var articles = 0
        var oldParagraphs = 0
        var newParagraphs = 0
        var splitParagraphs = 0
        /// Its own save failed: nothing changed, and the next launch plans it again.
        var rolledBack = false
    }

    /// Paragraph layout v3 (paragraphs over 1,200 characters split at sentence ends, see
    /// `ParagraphSplitter`) and any later `ListenHTMLBlocks.version`: for every page holding text
    /// on older listen blocks, rebuild its paragraphs and move its position to the same sentence.
    /// Once that is saved, its cached audio is aligned (pieces whose chunks line up are sliced,
    /// shifted paragraphs move, only the rest re-renders), and the crash-resume point and any
    /// pending bake job are remapped (`planAlign`). Idempotent: pages are stamped with the
    /// version. Logged per page (`paragraph_layout_migration`). Saves, unless the caller batches
    /// it into its own save; a save that fails is rolled back with its planned audio work, so a
    /// later save can't store it against pages that have changed since.
    @discardableResult
    func migrateParagraphLayout(saving: Bool = true) -> LayoutMigrationReport {
        var report = LayoutMigrationReport()
        let version = ListenHTMLBlocks.version
        let stale = ((try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.listenBlocksVersion < version }))) ?? [])
            .filter(\.hasText)
        guard !stale.isEmpty else { return report }
        for article in stale {
            let t0 = ListenTimingLog.now()
            // The list the stored position and audio refer to: the stored v2 blocks when present,
            // else what the pre-split rules produce from the saved HTML.
            let storedOld = article.listenBlocksVersion == 2 ? Article.decodeAnyListenParagraphs(article.listenBlocksData) : nil
            let old = storedOld.map { ParagraphDocument(parts: $0) }
                ?? ParagraphDocument.forListening(plainText: article.plainText, cleanedHTML: article.cleanedHTML,
                                                  matchingTitle: article.givenTitle, splitLong: false)
            let new = Article.buildListenDocument(plainText: article.plainText, cleanedHTML: article.cleanedHTML, title: article.givenTitle)
            let before = ParagraphPositionMap.Position(paragraph: article.positionParagraph, utf16Offset: article.positionUTF16)
            let after = ParagraphPositionMap.map(paragraph: before.paragraph, utf16Offset: before.utf16Offset, from: old, to: new)
            article.storeListenParagraphs(new.paragraphs)
            article.positionParagraph = after.paragraph
            article.positionUTF16 = after.utf16Offset
            if let key = article.key { planAlign(key: key, old: old.paragraphs, new: new.paragraphs) }

            let splitCount = old.paragraphs.filter { ParagraphSplitter.pieces($0).count > 1 }.count
            report.articles += 1
            report.oldParagraphs += old.count
            report.newParagraphs += new.count
            report.splitParagraphs += splitCount
            ListenTimingLog.log("paragraph_layout_migration", [
                "key": article.key.map(ListenTimingLog.shortKey) ?? "-", "old_paragraphs": old.count,
                "new_paragraphs": new.count, "split": splitCount, "from_stored": storedOld != nil,
                "pos_old": "\(before.paragraph)@\(before.utf16Offset)", "pos_new": "\(after.paragraph)@\(after.utf16Offset)",
                "ms": ListenTimingLog.ms(since: t0),
            ])
            log("layout v\(version) \(Self.short(article.key)): paragraphs \(old.count)→\(new.count) (split \(splitCount)), position \(before.paragraph)→\(after.paragraph)")
        }
        if saving, !commit("layout migration") {
            rollBack()
            report.rolledBack = true
            log("layout migration: save failed, rolled back; the next launch plans it again")
        }
        return report
    }

    // MARK: - Prune

    struct PruneReport: Equatable {
        var deletedArticles = 0
        var clearedLinkCaches = 0
    }

    /// Pages not in the Library and not played for 7 days are deleted (a removed page never
    /// played counts as played long ago: it goes at the next launch), except the page the Now
    /// Playing bar resumes (`LibraryQueries.lastPlayed`). Their audio is already ephemeral; the
    /// audio cache's own age and size prune removes it. Link pages' text caches unplayed for 7
    /// days are cleared; the links stay. A failed save is rolled back (the next launch prunes).
    @discardableResult
    func pruneUnsaved() -> PruneReport {
        var report = PruneReport()
        let cutoff = now().addingTimeInterval(-Self.unsavedKeepInterval)
        let lastPlayed = (try? context.fetch(LibraryQueries.lastPlayed))?.first
        for article in (try? context.fetch(LibraryQueries.prunable(before: cutoff))) ?? [] where article !== lastPlayed {
            log("prune \(Self.short(article.key)) (not in Library, last played \(article.lastPlayedAt.map { "\($0)" } ?? "never"))")
            context.delete(article)
            report.deletedArticles += 1
        }
        for article in (try? context.fetch(LibraryQueries.staleLinkCaches(before: cutoff))) ?? [] where article !== lastPlayed {
            clearText(article)
            article.lastPlayedAt = nil
            report.clearedLinkCaches += 1
        }
        if report != PruneReport(), !commit("prune") { rollBack() }
        return report
    }

    // MARK: - Finished chapters' audio (D7)

    /// Deletes the audio of finished pages more than 2 behind a book's or series' place (D7; a
    /// folder you made keeps its audio); the text stays. A direct delete, not ephemeral marking, so the unsaved-audio size cap is
    /// unaffected. Audio held for unfinished library work (`ArticleAudioCache.held`) stays: that
    /// work still needs it. Returns how many chapters lost their audio.
    @discardableResult
    func trimFinishedAudio(folder: Folder) -> Int {
        guard folder.kind.isBookOrSeries, let place = folder.currentArticleKey else { return 0 }
        let order = articles(in: folder)
        guard let current = order.firstIndex(where: { $0.key == place }), current > 2 else { return 0 }
        var trimmed = 0
        for article in order[..<(current - 2)] where article.finishedAt != nil {
            // C134: prepared audio is never trimmed; only audio from listening is.
            guard let key = article.key, audio.audioCache.hasCache(for: key), !audio.audioCache.held.contains(key),
                  !audio.isPrepared(key) else { continue }
            try? audio.clearListenAudio(for: key)
            trimmed += 1
        }
        if trimmed > 0 { log("trimmed audio of \(trimmed) finished chapters in \(folder.name)") }
        return trimmed
    }

    // MARK: - Crash resume

    /// The page a crash-resume target names: its full key, or the 8-character prefix older crash
    /// markers wrote.
    func article(matching target: ListenResumeTarget) -> Article? {
        if let key = UUID(uuidString: target.articleKey) { return article(key: key) }
        let articles = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        return articles.first { $0.key.map(target.matches) == true }
    }
}
