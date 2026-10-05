import Foundation
import SwiftData

/// The launch dedupe pass. One device never makes these cases, but sync (later) and a migration
/// copy can: two pages for one address, two Favorites, two copies of a book, a folder cycle.
/// Handling them now means sync adds no new code paths.
extension LibraryStore {
    struct DedupeReport: Equatable {
        var mergedFolders = 0
        var mergedPages = 0
        var brokenCycles = 0
        var movedOutOfFixed = 0
        var repairedFolderIDs = 0
    }

    /// Runs every rule, folders first (so a book's pages don't end up split), then saves once
    /// (unless the caller batches it into its own save). A failed save is rolled back with its
    /// planned audio work; the next launch merges again.
    @discardableResult
    func dedupe(saving: Bool = true) -> DedupeReport {
        var report = DedupeReport()
        dedupeSourceFolders(&report)
        dedupeFavorites(&report)
        moveSubfoldersOutOfFixed(&report)
        breakCycles(&report)
        repairFolderIDs(&report)
        dedupePages(&report)
        if report != DedupeReport() {
            if saving, !commit("dedupe") {
                rollBack()
                log("dedupe: save failed, rolled back; the next launch merges again")
                return report
            }
            log("dedupe: \(report)")
        }
        return report
    }

    // MARK: - Folders

    /// Two books or series with one `sourceIdentifier` merge into the older one, by page key.
    private func dedupeSourceFolders(_ report: inout DedupeReport) {
        let folders = ((try? context.fetch(FetchDescriptor<Folder>())) ?? []).filter { $0.kind.isFixed && $0.sourceIdentifier != nil }
        let groups = Dictionary(grouping: folders) { "\($0.kindRaw)|\($0.sourceIdentifier ?? "")" }.values.filter { $0.count > 1 }
        for group in groups {
            let ordered = group.sorted(by: Self.olderFirst)
            let keeper = ordered[0]
            for extra in ordered.dropFirst() {
                // Pages whose key the keeper already has are merged by the page pass below.
                for page in playOrder(of: extra) { page.setFolder(keeper) }
                if (extra.lastPlayedAt ?? .distantPast) > (keeper.lastPlayedAt ?? .distantPast) {
                    keeper.currentPageKey = extra.currentPageKey
                    keeper.lastPlayedAt = extra.lastPlayedAt
                    keeper.finishedAt = extra.finishedAt
                }
                if keeper.coverData == nil { keeper.coverData = extra.coverData }
                for child in extra.children ?? [] { child.parent = keeper.parent }
                log("dedupe folder \(extra.name) → \(keeper.name)")
                context.delete(extra)
                report.mergedFolders += 1
            }
        }
    }

    /// Two Favorites folders: the newer one's contents move into the older, after its own.
    private func dedupeFavorites(_ report: inout DedupeReport) {
        let all = (try? context.fetch(LibraryQueries.favorites)) ?? []
        guard all.count > 1 else { return }
        let ordered = all.sorted(by: Self.olderFirst)
        let keeper = ordered[0]
        for extra in ordered.dropFirst() {
            var pageKey = nextSortKey(in: keeper)
            for page in pages(in: extra) {
                page.setFolder(keeper)
                page.sortKey = pageKey
                pageKey += 1
            }
            var folderKey = nextFolderSortKey(in: keeper)
            for child in subfolders(of: extra) {
                child.parent = keeper
                child.sortKey = folderKey
                folderKey += 1
            }
            context.delete(extra)
            report.mergedFolders += 1
        }
        keeper.parent = nil
    }

    /// Books and series have no subfolders: one found inside moves to the book's parent.
    private func moveSubfoldersOutOfFixed(_ report: inout DedupeReport) {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for folder in folders where folder.parent?.kind.isFixed == true {
            folder.parent = folder.parent?.parent
            report.movedOutOfFixed += 1
        }
        for favorites in folders where favorites.kind == .favorites && favorites.parent != nil {
            favorites.parent = nil
            report.movedOutOfFixed += 1
        }
    }

    /// A folder cycle (device A moved X into Y while B moved Y into X): the newest folder in it
    /// moves to the top level.
    private func breakCycles(_ report: inout DedupeReport) {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for start in folders {
            var seen: [Folder] = []
            var next: Folder? = start
            while let folder = next {
                if let i = seen.firstIndex(where: { $0 === folder }) {
                    let cycle = seen[i...]
                    let newest = cycle.max { $0.createdAt < $1.createdAt || ($0.createdAt == $1.createdAt && $0.id.uuidString < $1.id.uuidString) }
                    newest?.parent = nil
                    report.brokenCycles += 1
                    break
                }
                seen.append(folder)
                next = folder.parent
            }
        }
    }

    /// `Page.folderID` disagreeing with `Page.folder`: the relationship wins.
    private func repairFolderIDs(_ report: inout DedupeReport) {
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        for page in pages where page.folderID != page.folder?.id {
            page.folderID = page.folder?.id
            report.repairedFolderIDs += 1
        }
    }

    // MARK: - Pages

    /// Pages sharing a key or a canonical URL become one, the keeper chosen by: saved over link;
    /// the furthest position; the latest play; the older. The keeper takes content it lacks, the
    /// other's audio, the earliest `addedAt` (a save is never lost) and the latest play; any
    /// place or crash-resume point on the other's key follows it.
    private func dedupePages(_ report: inout DedupeReport) {
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        // Union by key and by canonical URL.
        var parent = Array(pages.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        var byKey: [UUID: Int] = [:]
        var byURL: [String: Int] = [:]
        for (i, page) in pages.enumerated() {
            if let key = page.key {
                if let j = byKey[key] { parent[root(i)] = root(j) } else { byKey[key] = i }
            }
            if let url = page.canonicalURL, !url.isEmpty {
                if let j = byURL[url] { parent[root(i)] = root(j) } else { byURL[url] = i }
            }
        }
        let groups = Dictionary(grouping: pages.indices, by: root).values.filter { $0.count > 1 }
        for group in groups {
            let members = group.map { pages[$0] }
            let keeper = members.min(by: Self.betterKeeper)!
            for extra in members where extra !== keeper {
                merge(extra, into: keeper)
                report.mergedPages += 1
            }
        }
    }

    private func merge(_ extra: Page, into keeper: Page) {
        // Folder: a book or series keeps its page; otherwise the keeper's, else the other's.
        if extra.isInFixedFolder && !keeper.isInFixedFolder {
            keeper.sortKey = extra.sortKey
            keeper.setFolder(extra.folder)
        } else if keeper.folder == nil, let folder = extra.folder {
            keeper.sortKey = extra.sortKey
            keeper.setFolder(folder)
        }
        if !keeper.hasText, extra.hasText {
            keeper.bodyHTML = extra.bodyHTML
            keeper.plainTextData = extra.plainTextData
            keeper.excerpt = extra.excerpt
            keeper.wordCount = extra.wordCount
        }
        if keeper.listenBlocksData == nil, extra.listenBlocksData != nil {
            keeper.listenBlocksData = extra.listenBlocksData
            keeper.listenBlocksVersion = extra.listenBlocksVersion
            keeper.paragraphCount = extra.paragraphCount
            keeper.detectedLanguageCode = extra.detectedLanguageCode
        }
        if keeper.artworkData == nil { keeper.artworkData = extra.artworkData }
        if keeper.urlString == nil { keeper.urlString = extra.urlString }
        if keeper.canonicalURL == nil { keeper.canonicalURL = extra.canonicalURL }
        if extra.isSaved { keeper.contentState = .saved }
        keeper.addedAt = [keeper.addedAt, extra.addedAt].compactMap { $0 }.min()
        if (extra.lastPlayedAt ?? .distantPast) > (keeper.lastPlayedAt ?? .distantPast) {
            keeper.lastPlayedAt = extra.lastPlayedAt
        }
        if keeper.key == nil { keeper.key = extra.key }
        if let from = extra.key, let to = keeper.key, from != to { mergeAudio(from: from, fromPage: extra, into: to, keeper: keeper) }
        log("dedupe page \(Self.short(extra.key)) → keeper \(Self.short(keeper.key)) (\(keeper.canonicalURL ?? "-"))")
        context.delete(extra)
    }

    /// Points every place at the keeper now; once this is saved, `from`'s audio moves under `to`
    /// (per-paragraph hashes decide what is reusable), its pending render is dropped, and the
    /// crash-resume point and the live session follow (`planMerge`).
    private func mergeAudio(from: UUID, fromPage: Page, into to: UUID, keeper: Page) {
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        for folder in folders where folder.currentPageKey == from { folder.currentPageKey = to }
        planMerge(from: from, into: to, fromParagraphs: fromPage.cachedListenParagraphs ?? [],
                  paragraphs: keeper.cachedListenParagraphs ?? [])
    }

    // MARK: - Orders

    /// Saved over link; the furthest position; the latest play; the older.
    static func betterKeeper(_ a: Page, _ b: Page) -> Bool {
        if a.isSaved != b.isSaved { return a.isSaved }
        if a.positionParagraph != b.positionParagraph { return a.positionParagraph > b.positionParagraph }
        if a.positionUTF16 != b.positionUTF16 { return a.positionUTF16 > b.positionUTF16 }
        let pa = a.lastPlayedAt ?? .distantPast, pb = b.lastPlayedAt ?? .distantPast
        if pa != pb { return pa > pb }
        let aa = a.addedAt ?? .distantFuture, ab = b.addedAt ?? .distantFuture
        if aa != ab { return aa < ab }
        return (a.key?.uuidString ?? "") < (b.key?.uuidString ?? "")
    }

    static func olderFirst(_ a: Folder, _ b: Folder) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
    }
}
