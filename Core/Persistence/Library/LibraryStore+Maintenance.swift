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
        let stale = ((try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.listenBlocksVersion < version }))) ?? [])
            .filter(\.hasText)
        guard !stale.isEmpty else { return report }
        for page in stale {
            let t0 = ListenTimingLog.now()
            // The list the stored position and audio refer to: the stored v2 blocks when present,
            // else what the pre-split rules produce from the saved HTML.
            let storedOld = page.listenBlocksVersion == 2 ? Page.decodeAnyListenParagraphs(page.listenBlocksData) : nil
            let old = storedOld.map { ParagraphDocument(parts: $0) }
                ?? ParagraphDocument.forListening(plainText: page.plainText, cleanedHTML: page.cleanedHTML,
                                                  matchingTitle: page.title, splitLong: false)
            let new = Page.buildListenDocument(plainText: page.plainText, cleanedHTML: page.cleanedHTML, title: page.title)
            let before = ParagraphPositionMap.Position(paragraph: page.positionParagraph, utf16Offset: page.positionUTF16)
            let after = ParagraphPositionMap.map(paragraph: before.paragraph, utf16Offset: before.utf16Offset, from: old, to: new)
            page.storeListenParagraphs(new.paragraphs)
            page.positionParagraph = after.paragraph
            page.positionUTF16 = after.utf16Offset
            if let key = page.key { planAlign(key: key, old: old.paragraphs, new: new.paragraphs) }

            let splitCount = old.paragraphs.filter { ParagraphSplitter.pieces($0).count > 1 }.count
            report.articles += 1
            report.oldParagraphs += old.count
            report.newParagraphs += new.count
            report.splitParagraphs += splitCount
            ListenTimingLog.log("paragraph_layout_migration", [
                "key": page.key.map(ListenTimingLog.shortKey) ?? "-", "old_paragraphs": old.count,
                "new_paragraphs": new.count, "split": splitCount, "from_stored": storedOld != nil,
                "pos_old": "\(before.paragraph)@\(before.utf16Offset)", "pos_new": "\(after.paragraph)@\(after.utf16Offset)",
                "ms": ListenTimingLog.ms(since: t0),
            ])
            log("layout v\(version) \(Self.short(page.key)): paragraphs \(old.count)→\(new.count) (split \(splitCount)), position \(before.paragraph)→\(after.paragraph)")
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
        var deletedPages = 0
        var clearedLinkCaches = 0
    }

    /// Pages not in the Library and not played for 7 days are deleted (a removed page never
    /// played counts as played long ago: it goes at the next launch), except the page played
    /// most recently (what the Now Playing bar restores). Their audio is already ephemeral; the
    /// audio cache's own age and size prune removes it. Link pages' text caches unplayed for 7
    /// days are cleared; the links stay. A failed save is rolled back (the next launch prunes).
    @discardableResult
    func pruneUnsaved() -> PruneReport {
        var report = PruneReport()
        let cutoff = now().addingTimeInterval(-Self.unsavedKeepInterval)
        var latest = FetchDescriptor<Page>(sortBy: [SortDescriptor(\Page.lastPlayedAt, order: .reverse)])
        latest.fetchLimit = 1
        let lastPlayed = (try? context.fetch(latest))?.first.flatMap { $0.lastPlayedAt == nil ? nil : $0 }
        for page in (try? context.fetch(LibraryQueries.prunable(before: cutoff))) ?? [] where page !== lastPlayed {
            log("prune \(Self.short(page.key)) (not in Library, last played \(page.lastPlayedAt.map { "\($0)" } ?? "never"))")
            context.delete(page)
            report.deletedPages += 1
        }
        for page in (try? context.fetch(LibraryQueries.staleLinkCaches(before: cutoff))) ?? [] where page !== lastPlayed {
            clearText(page)
            page.lastPlayedAt = nil
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
        guard folder.kind.isBookOrSeries, let place = folder.currentPageKey else { return 0 }
        let order = pages(in: folder)
        guard let current = order.firstIndex(where: { $0.key == place }), current > 2 else { return 0 }
        var trimmed = 0
        for page in order[..<(current - 2)] where page.finishedAt != nil {
            guard let key = page.key, tts.audioCache.hasCache(for: key), !tts.audioCache.held.contains(key) else { continue }
            try? tts.clearListenAudio(for: key)
            trimmed += 1
        }
        if trimmed > 0 { log("trimmed audio of \(trimmed) finished chapters in \(folder.name)") }
        return trimmed
    }

    // MARK: - Crash resume

    /// The page a crash-resume target names: its full key, or the 8-character prefix older crash
    /// markers wrote.
    func page(matching target: ListenResumeTarget) -> Page? {
        if let key = UUID(uuidString: target.articleKey) { return page(key: key) }
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        return pages.first { $0.key.map(target.matches) == true }
    }
}
