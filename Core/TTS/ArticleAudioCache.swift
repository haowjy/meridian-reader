import Foundation
import Observation

@MainActor
@Observable
final class ArticleAudioCache {
    enum Status: Equatable {
        case missing
        case partial(ready: Int, total: Int)
        case ready(paragraphCount: Int)
        case baking(fraction: Double)
    }

    struct IndexFile: Codable, Equatable {
        var engineID: String
        var voiceID: String
        var rate: Float?
        var createdAt: Date
        var paragraphs: [ParagraphEntry]

        struct ParagraphEntry: Codable, Equatable {
            var index: Int
            var file: String
            var duration: Double
            /// `ArticleIdentity.paragraphHash` of the text this CAF was rendered from.
            /// nil for caches written before v2 identity (unverifiable; see `stampMissingHashes`).
            var textHash: String? = nil
            /// Durations of the synth chunks stitched into this CAF (nil = single render).
            /// Lets a player resume mid-paragraph at a chunk boundary (`startTime`).
            var chunkDurations: [Double]? = nil
            /// Engine / voice of this CAF when it differs from the index's `engineID`/`voiceID`:
            /// a paragraph not yet re-rendered after a voice or engine switch ("stale"). Stale
            /// units are playable (`playableAudioURL`) but never count as ready for the current
            /// voice; re-rendering the paragraph overwrites the file. nil = the index's.
            var engineID: String? = nil
            var voiceID: String? = nil
        }

        func engine(of e: ParagraphEntry) -> String { e.engineID ?? engineID }
        func voice(of e: ParagraphEntry) -> String { e.voiceID ?? voiceID }
        func matches(_ e: ParagraphEntry, engineID: String, voiceID: String) -> Bool {
            engine(of: e) == engineID && voice(of: e) == voiceID
        }

        /// Same units, re-homed onto a new index engine/voice: entries rendered with another
        /// engine/voice get it stamped explicitly; entries matching the new one are un-stamped.
        func retargeted(engineID newEngine: String, voiceID newVoice: String) -> IndexFile {
            var out = self
            out.paragraphs = paragraphs.map { e in
                var e2 = e
                let eng = engine(of: e), voi = voice(of: e)
                let same = eng == newEngine && voi == newVoice
                e2.engineID = same ? nil : eng
                e2.voiceID = same ? nil : voi
                return e2
            }
            out.engineID = newEngine
            out.voiceID = newVoice
            return out
        }
    }

    private(set) var bakeProgress: [UUID: Double] = [:]
    /// Bumped when CAF index/files change so reading UI can refresh bake-ready marks.
    private(set) var contentRevision: UInt64 = 0
    private let fileManager: FileManager
    /// Cache root (`Application Support/TTSCache` in the app; a temp dir in tests).
    let root: URL

    init(fileManager: FileManager = .default, root: URL = ArticleAudioCache.cacheRoot) {
        self.fileManager = fileManager
        self.root = root
    }

    nonisolated static var cacheRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TTSCache", isDirectory: true)
    }

    func directory(for articleID: UUID) -> URL {
        root.appendingPathComponent(articleID.uuidString, isDirectory: true)
    }

    func indexURL(for articleID: UUID) -> URL {
        directory(for: articleID).appendingPathComponent("index.json")
    }

    func hasCache(for articleID: UUID) -> Bool {
        fileManager.fileExists(atPath: indexURL(for: articleID).path)
    }

    func status(for articleID: UUID, expectedParagraphs: Int? = nil) -> Status {
        if let progress = bakeProgress[articleID] { return .baking(fraction: progress) }
        guard let index = try? loadIndex(for: articleID) else { return .missing }
        let total = expectedParagraphs ?? index.paragraphs.count
        if total == 0 { return .missing }
        // Units in the index's (latest) engine/voice only; stale units of a previous voice don't count.
        let current = index.paragraphs.filter { $0.engineID == nil && $0.voiceID == nil }
        let ready = current.filter {
            fileManager.fileExists(atPath: directory(for: articleID).appendingPathComponent($0.file).path)
        }.count
        if ready >= total, ready == current.count {
            return .ready(paragraphCount: ready)
        }
        if ready == 0 { return .missing }
        return .partial(ready: ready, total: max(total, current.count))
    }

    /// True when a complete bake for this engine/voice already exists.
    func isReady(articleID: UUID, engineID: String, voiceID: String, paragraphCount: Int) -> Bool {
        guard paragraphCount > 0 else { return false }
        return readyIndices(articleID: articleID, paragraphCount: paragraphCount,
                            engineID: engineID, voiceID: voiceID).count == paragraphCount
    }

    func loadIndex(for articleID: UUID) throws -> IndexFile {
        try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: indexURL(for: articleID)))
    }

    /// CAF for this paragraph rendered with exactly this engine/voice (bake state, queue).
    func audioURL(articleID: UUID, paragraphIndex: Int, engineID: String, voiceID: String) -> URL? {
        guard let index = try? loadIndex(for: articleID),
              let entry = index.paragraphs.first(where: {
                  $0.index == paragraphIndex && index.matches($0, engineID: engineID, voiceID: voiceID)
              })
        else { return nil }
        let url = directory(for: articleID).appendingPathComponent(entry.file)
        return isUsableAudioFile(url) ? url : nil
    }

    /// Playback: the current engine/voice's CAF, else a stale one (older voice/engine) until the
    /// paragraph is re-rendered — so a voice switch never makes baked audio unplayable.
    func playableAudioURL(articleID: UUID, paragraphIndex: Int, engineID: String, voiceID: String) -> URL? {
        if let exact = audioURL(articleID: articleID, paragraphIndex: paragraphIndex,
                                engineID: engineID, voiceID: voiceID) {
            return exact
        }
        guard let index = try? loadIndex(for: articleID),
              let entry = index.paragraphs.first(where: { $0.index == paragraphIndex })
        else { return nil }
        let url = directory(for: articleID).appendingPathComponent(entry.file)
        return isUsableAudioFile(url) ? url : nil
    }

    /// Paragraph indices with a usable CAF for this engine/voice (stale units excluded).
    func readyIndices(
        articleID: UUID,
        paragraphCount: Int,
        engineID: String,
        voiceID: String
    ) -> Set<Int> {
        _ = contentRevision
        guard paragraphCount > 0 else { return [] }
        var ready = Set<Int>()
        if let index = try? loadIndex(for: articleID) {
            for entry in index.paragraphs
            where entry.index >= 0 && entry.index < paragraphCount
                && index.matches(entry, engineID: engineID, voiceID: voiceID) {
                let url = directory(for: articleID).appendingPathComponent(entry.file)
                if isUsableAudioFile(url) { ready.insert(entry.index) }
            }
        }
        return ready
    }

    /// Paragraph indices still missing a usable CAF for this engine/voice.
    func missingIndices(
        articleID: UUID,
        paragraphCount: Int,
        engineID: String,
        voiceID: String
    ) -> [Int] {
        let ready = readyIndices(
            articleID: articleID,
            paragraphCount: paragraphCount,
            engineID: engineID,
            voiceID: voiceID
        )
        return (0..<paragraphCount).filter { !ready.contains($0) }
    }

    private func bumpContentRevision() {
        contentRevision &+= 1
    }

    func deleteAudio(for articleID: UUID) throws {
        bakeProgress[articleID] = nil
        let dir = directory(for: articleID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        bumpContentRevision()
    }

    /// Persist one successfully rendered unit into the bake cache (default path for live + batch).
    /// Copies `sourceURL` into `p-NNNN.caf` and updates `index.json` atomically.
    @discardableResult
    func storeParagraph(
        articleID: UUID,
        paragraphIndex: Int,
        sourceURL: URL,
        duration: TimeInterval,
        engineID: String,
        voiceID: String,
        rate: Float,
        text: String? = nil,
        chunkDurations: [Double]? = nil
    ) throws -> URL {
        guard isUsableAudioFile(sourceURL) else {
            throw NSError(
                domain: "ArticleAudioCache",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to store empty/tiny CAF at \(paragraphIndex)"]
            )
        }
        let dir = directory(for: articleID)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = String(format: "p-%04d.caf", paragraphIndex)
        let dest = dir.appendingPathComponent(fileName)
        if sourceURL.standardizedFileURL != dest.standardizedFileURL {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: sourceURL, to: dest)
        }

        // One voice per article: units of another engine/voice stay (stamped stale, still
        // playable) until their paragraph is re-rendered; this paragraph's old file was just
        // replaced above. `finalizeVoiceSwitch` drops any leftovers once the article is complete.
        var entries: [IndexFile.ParagraphEntry] = []
        if let existing = try? loadIndex(for: articleID) {
            entries = existing.retargeted(engineID: engineID, voiceID: voiceID).paragraphs.filter {
                $0.index != paragraphIndex
                    && fileManager.fileExists(atPath: dir.appendingPathComponent($0.file).path)
            }
        }
        entries.append(.init(
            index: paragraphIndex,
            file: fileName,
            duration: duration,
            textHash: text.map(ArticleIdentity.paragraphHash),
            chunkDurations: chunkDurations
        ))
        entries.sort { $0.index < $1.index }

        let index = IndexFile(
            engineID: engineID,
            voiceID: voiceID,
            rate: rate,
            createdAt: Date(),
            paragraphs: entries
        )
        try JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
        bumpContentRevision()
        return dest
    }

    /// Index entry for a ready paragraph (for chunk-boundary offsets).
    func entry(articleID: UUID, paragraphIndex: Int) -> IndexFile.ParagraphEntry? {
        (try? loadIndex(for: articleID))?.paragraphs.first { $0.index == paragraphIndex }
    }

    // MARK: - Synth chunk scratch (GlobalSynthQueue)

    /// `<article>/chunks/p-NNNN-<texthash>/c-KK.caf` — per-chunk renders of a paragraph that is
    /// still being built. Stitched into `p-NNNN.caf` when every chunk is present.
    func chunkDirectory(articleID: UUID, paragraphIndex: Int, textHash: String) -> URL {
        directory(for: articleID)
            .appendingPathComponent("chunks", isDirectory: true)
            .appendingPathComponent(String(format: "p-%04d-", paragraphIndex) + textHash, isDirectory: true)
    }

    func chunkURL(articleID: UUID, paragraphIndex: Int, textHash: String, chunk: Int) -> URL {
        chunkDirectory(articleID: articleID, paragraphIndex: paragraphIndex, textHash: textHash)
            .appendingPathComponent(String(format: "c-%02d.caf", chunk))
    }

    func isUsableChunk(_ url: URL) -> Bool { isUsableAudioFile(url) }

    /// Drop chunk scratch for one article (never while it is the live playback session).
    func removeChunkScratch(for articleID: UUID) {
        let dir = directory(for: articleID).appendingPathComponent("chunks", isDirectory: true)
        try? fileManager.removeItem(at: dir)
    }

    /// Drop chunk scratch for one article except the dirs that still match `paragraphs`
    /// (same index + text hash): those hold finished chunks of a paragraph the queue is
    /// baking right now. Wiping them made the worker synthesize the same chunks again —
    /// extra Core ML calls, each one more exposure to the Kokoro libBNNS crash (#844).
    func removeChunkScratch(for articleID: UUID, keepingCurrent paragraphs: [String]) {
        let dir = directory(for: articleID).appendingPathComponent("chunks", isDirectory: true)
        guard let subdirs = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        let keep = Set(paragraphs.indices.map {
            String(format: "p-%04d-", $0) + ArticleIdentity.paragraphHash(paragraphs[$0])
        })
        for name in subdirs where !keep.contains(name) {
            try? fileManager.removeItem(at: dir.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// Launch-time cleanup: nothing is playing yet, so all chunk scratch is disposable.
    func removeAllChunkScratch() {
        guard let dirs = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }
        for dir in dirs {
            try? fileManager.removeItem(at: dir.appendingPathComponent("chunks", isDirectory: true))
        }
    }

    private func isUsableAudioFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 256
    }
}

/// Explicit bake order for one article. Single Core ML worker walks this plan.
/// Policy: priority stretch first (from `priorityStart` → end), then optionally return to top
/// for any missing units below the jump/playhead so the full article lands on disk.
struct BakePriorityPlan: Equatable, Sendable {
    /// First index of the priority stretch (save → 0; listen/jump → selected paragraph).
    var priorityStart: Int
    /// After priority stretch finishes, bake missing indices in `0..<priorityStart`.
    var fillGapsFromTopAfterPriority: Bool
    var paragraphCount: Int

    static func topDown(paragraphCount: Int) -> BakePriorityPlan {
        BakePriorityPlan(
            priorityStart: 0,
            fillGapsFromTopAfterPriority: false,
            paragraphCount: paragraphCount
        )
    }

    static func fromPlayhead(_ start: Int, paragraphCount: Int) -> BakePriorityPlan {
        let clamped = max(0, min(start, max(paragraphCount - 1, 0)))
        return BakePriorityPlan(
            priorityStart: clamped,
            fillGapsFromTopAfterPriority: true,
            paragraphCount: paragraphCount
        )
    }

    /// Ordered indices still needing work. `missing` should be ascending.
    func orderedWork(missing: [Int]) -> [Int] {
        let start = max(0, min(priorityStart, paragraphCount))
        var order: [Int] = []
        let missingSet = Set(missing)
        for i in start..<paragraphCount where missingSet.contains(i) {
            order.append(i)
        }
        if fillGapsFromTopAfterPriority {
            for i in 0..<start where missingSet.contains(i) {
                order.append(i)
            }
        }
        return order
    }
}

// MARK: - Ephemeral meta, rekey, prune

extension ArticleAudioCache {
    struct CacheMeta: Codable, Equatable {
        enum Kind: String, Codable { case ephemeral, saved }
        var kind: Kind
        var canonicalURL: String?
        var createdAt: Date
        var lastAccessAt: Date
    }

    private func metaURL(for articleID: UUID) -> URL {
        directory(for: articleID).appendingPathComponent("meta.json")
    }

    func loadMeta(for articleID: UUID) -> CacheMeta? {
        guard let data = try? Data(contentsOf: metaURL(for: articleID)) else { return nil }
        return try? JSONDecoder().decode(CacheMeta.self, from: data)
    }

    func markEphemeral(cacheKey: UUID, canonicalURL: String? = nil, lastAccess: Date = Date()) {
        let dir = directory(for: cacheKey)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = loadMeta(for: cacheKey)
        let meta = CacheMeta(
            kind: .ephemeral,
            canonicalURL: canonicalURL ?? existing?.canonicalURL,
            createdAt: existing?.createdAt ?? Date(),
            lastAccessAt: lastAccess
        )
        try? JSONEncoder().encode(meta).write(to: metaURL(for: cacheKey), options: .atomic)
    }

    func markSaved(cacheKey: UUID) {
        let dir = directory(for: cacheKey)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        let existing = loadMeta(for: cacheKey)
        let meta = CacheMeta(
            kind: .saved,
            canonicalURL: existing?.canonicalURL,
            createdAt: existing?.createdAt ?? Date(),
            lastAccessAt: Date()
        )
        try? JSONEncoder().encode(meta).write(to: metaURL(for: cacheKey), options: .atomic)
    }

    /// Move/merge CAF cache from ephemeral key → saved UUID. Prefer rename when dest empty.
    func rekeyCache(from oldKey: UUID, to newKey: UUID) throws {
        guard oldKey != newKey else {
            markSaved(cacheKey: newKey)
            return
        }
        let src = directory(for: oldKey)
        let dst = directory(for: newKey)
        guard fileManager.fileExists(atPath: src.path) else {
            markSaved(cacheKey: newKey)
            return
        }

        if !fileManager.fileExists(atPath: dst.path) {
            try fileManager.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: src, to: dst)
            markSaved(cacheKey: newKey)
            bakeProgress[newKey] = bakeProgress[oldKey]
            bakeProgress[oldKey] = nil
            return
        }

        // Dest exists — copy any missing paragraph files + merge index.
        let srcIndex = try? loadIndex(for: oldKey)
        let dstIndex = try? loadIndex(for: newKey)
        var dstEntries: [IndexFile.ParagraphEntry] = []
        // Default for index files written before engine keys existed (Chatterbox Nano era).
        var engineID = Self.legacyEngineID
        var voiceID = "system"
        var rate: Float? = nil
        if let srcIndex {
            engineID = srcIndex.engineID
            voiceID = srcIndex.voiceID
        } else if let dstIndex {
            engineID = dstIndex.engineID
            voiceID = dstIndex.voiceID
        }
        if let dstIndex {
            dstEntries = dstIndex.retargeted(engineID: engineID, voiceID: voiceID).paragraphs
            rate = dstIndex.rate
        }
        if let srcIndex {
            rate = srcIndex.rate
            for entry in srcIndex.paragraphs {
                let srcFile = src.appendingPathComponent(entry.file)
                let dstFile = dst.appendingPathComponent(entry.file)
                guard isUsableAudioFile(srcFile) else { continue }
                // Keep the destination's unit (and its text hash) when it already has one.
                guard !isUsableAudioFile(dstFile) else { continue }
                if fileManager.fileExists(atPath: dstFile.path) {
                    try fileManager.removeItem(at: dstFile)
                }
                try fileManager.copyItem(at: srcFile, to: dstFile)
                dstEntries.removeAll { $0.index == entry.index }
                dstEntries.append(entry)
            }
        }
        dstEntries.sort { $0.index < $1.index }
        let index = IndexFile(
            engineID: engineID,
            voiceID: voiceID,
            rate: rate,
            createdAt: Date(),
            paragraphs: dstEntries
        )
        try JSONEncoder().encode(index).write(to: indexURL(for: newKey), options: .atomic)
        bumpContentRevision()
        markSaved(cacheKey: newKey)
        try? deleteAudio(for: oldKey)
    }

    /// Prune ephemeral caches older than `maxAge` or when total ephemeral size exceeds `maxBytes`.
    /// Saved caches are never pruned here. Choice: survive leaving Reader + app restart; TTL by age/size.
    @discardableResult
    func pruneEphemeral(
        maxAge: TimeInterval = 7 * 24 * 60 * 60,
        maxBytes: Int64 = 500 * 1024 * 1024
    ) -> (removed: Int, freedBytes: Int64) {
        let root = self.root
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        struct Entry {
            var id: UUID
            var url: URL
            var meta: CacheMeta
            var bytes: Int64
        }

        var ephemeral: [Entry] = []
        let now = Date()
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let id = UUID(uuidString: dir.lastPathComponent) else { continue }
            guard let meta = loadMeta(for: id), meta.kind == .ephemeral else { continue }
            let bytes = directorySize(dir)
            ephemeral.append(Entry(id: id, url: dir, meta: meta, bytes: bytes))
        }

        var removed = 0
        var freed: Int64 = 0

        // Age prune
        for entry in ephemeral {
            let age = now.timeIntervalSince(entry.meta.lastAccessAt)
            if age > maxAge {
                try? deleteAudio(for: entry.id)
                removed += 1
                freed += entry.bytes
            }
        }

        // Reload survivors for size budget (LRU by lastAccessAt)
        ephemeral = ephemeral.filter { loadMeta(for: $0.id)?.kind == .ephemeral }
        ephemeral.sort { $0.meta.lastAccessAt < $1.meta.lastAccessAt }
        var total = ephemeral.reduce(Int64(0)) { $0 + $1.bytes }
        var i = 0
        while total > maxBytes, i < ephemeral.count {
            let entry = ephemeral[i]
            i += 1
            // Skip if already deleted by age
            guard fileManager.fileExists(atPath: entry.url.path) else { continue }
            try? deleteAudio(for: entry.id)
            removed += 1
            freed += entry.bytes
            total -= entry.bytes
        }
        return (removed, freed)
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Per-paragraph text reconciliation (identity v2)

extension ArticleAudioCache {
    struct ReconcileResult: Equatable {
        var kept = 0
        var remapped = 0
        var dropped = 0
        var unverified = 0
        var changed: Bool { remapped > 0 || dropped > 0 }
    }

    /// Stamp entries written before v2 (no `textHash`) with the text they were rendered from.
    /// Only call with paragraphs known to match the cache (e.g. the saved copy's stored blocks,
    /// or content whose legacy v1 key equalled this cache dir).
    func stampMissingHashes(articleID: UUID, paragraphs: [String]) {
        guard var index = try? loadIndex(for: articleID) else { return }
        var changed = false
        for i in index.paragraphs.indices where index.paragraphs[i].textHash == nil {
            let p = index.paragraphs[i].index
            guard paragraphs.indices.contains(p) else { continue }
            index.paragraphs[i].textHash = ArticleIdentity.paragraphHash(paragraphs[p])
            changed = true
        }
        guard changed else { return }
        try? JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
    }

    /// Align cached CAFs with `paragraphs` (current listen blocks for this article key):
    /// keep units whose text hash still matches, move units whose paragraph shifted to its new
    /// index, and drop units whose text no longer exists. Unhashed legacy entries are kept.
    @discardableResult
    func reconcile(articleID: UUID, paragraphs: [String]) -> ReconcileResult {
        var result = ReconcileResult()
        guard var index = try? loadIndex(for: articleID), !index.paragraphs.isEmpty else { return result }
        let dir = directory(for: articleID)
        let currentHashes = paragraphs.map(ArticleIdentity.paragraphHash)
        var targetsByHash: [String: [Int]] = [:]
        for (i, h) in currentHashes.enumerated() { targetsByHash[h, default: []].append(i) }

        var final: [Int: IndexFile.ParagraphEntry] = [:]
        var moves: [(entry: IndexFile.ParagraphEntry, to: Int)] = []
        var toDelete: [IndexFile.ParagraphEntry] = []

        // Pass 1: exact matches / unverifiable keep their slot.
        var pending: [IndexFile.ParagraphEntry] = []
        for entry in index.paragraphs {
            guard isUsableAudioFile(dir.appendingPathComponent(entry.file)) else { continue }
            guard let hash = entry.textHash else {
                if paragraphs.indices.contains(entry.index), final[entry.index] == nil {
                    final[entry.index] = entry
                    result.unverified += 1
                } else {
                    toDelete.append(entry)
                }
                continue
            }
            if currentHashes.indices.contains(entry.index), currentHashes[entry.index] == hash,
               final[entry.index] == nil {
                final[entry.index] = entry
                result.kept += 1
            } else {
                pending.append(entry)
            }
        }
        // Pass 2: shifted paragraphs move to the nearest free index with the same text.
        for entry in pending {
            let candidates = (targetsByHash[entry.textHash ?? ""] ?? []).filter { final[$0] == nil }
            if let target = candidates.min(by: { abs($0 - entry.index) < abs($1 - entry.index) }) {
                var moved = entry
                moved.index = target
                moved.file = String(format: "p-%04d.caf", target)
                final[target] = moved
                moves.append((entry, target))
                result.remapped += 1
            } else {
                toDelete.append(entry)
                result.dropped += 1
            }
        }
        guard result.changed || !toDelete.isEmpty else { return result }

        // Two-phase rename so swaps cannot clobber each other.
        var staged: [(URL, URL)] = []
        for move in moves {
            let src = dir.appendingPathComponent(move.entry.file)
            let tmp = dir.appendingPathComponent("r-\(UUID().uuidString).caf")
            if (try? fileManager.moveItem(at: src, to: tmp)) != nil {
                staged.append((tmp, dir.appendingPathComponent(String(format: "p-%04d.caf", move.to))))
            } else {
                final[move.to] = nil
            }
        }
        let keptFiles = Set(final.values.map(\.file))
        for entry in toDelete where !keptFiles.contains(entry.file) {
            try? fileManager.removeItem(at: dir.appendingPathComponent(entry.file))
        }
        for (tmp, dst) in staged {
            if fileManager.fileExists(atPath: dst.path) { try? fileManager.removeItem(at: dst) }
            try? fileManager.moveItem(at: tmp, to: dst)
        }
        index.paragraphs = final.values.sorted { $0.index < $1.index }
        index.createdAt = Date()
        try? JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
        bumpContentRevision()
        return result
    }
}

// MARK: - One voice per article, retired engines, orphans

extension ArticleAudioCache {
    /// Engine id assumed for index files written before engine keys existed (Chatterbox Nano era).
    nonisolated static let legacyEngineID = "local.chatterbox-nano"

    /// Once every paragraph `0..<paragraphCount` has a CAF in `engineID`/`voiceID`, delete any
    /// remaining units of other voices/engines (e.g. indices past the end). Returns bytes freed.
    @discardableResult
    func finalizeVoiceSwitch(articleID: UUID, paragraphCount: Int, engineID: String, voiceID: String) -> Int64 {
        guard paragraphCount > 0, var index = try? loadIndex(for: articleID) else { return 0 }
        let stale = index.paragraphs.filter { !index.matches($0, engineID: engineID, voiceID: voiceID) }
        guard !stale.isEmpty,
              readyIndices(articleID: articleID, paragraphCount: paragraphCount,
                           engineID: engineID, voiceID: voiceID).count == paragraphCount
        else { return 0 }
        let dir = directory(for: articleID)
        let keptFiles = Set(index.paragraphs.filter { index.matches($0, engineID: engineID, voiceID: voiceID) }.map(\.file))
        var freed: Int64 = 0
        for e in stale where !keptFiles.contains(e.file) {
            let url = dir.appendingPathComponent(e.file)
            freed += FileSizes.allocatedBytes(at: url, fileManager: fileManager)
            try? fileManager.removeItem(at: url)
        }
        index = index.retargeted(engineID: engineID, voiceID: voiceID)
        index.paragraphs.removeAll { $0.engineID != nil || $0.voiceID != nil }
        try? JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
        bumpContentRevision()
        return freed
    }

    struct PurgeReport: Equatable {
        var articles = 0
        var paragraphs = 0
        var bytes: Int64 = 0
        var orphanFiles = 0
        var orphanBytes: Int64 = 0
    }

    /// Delete every cached unit rendered by `engineID` (all articles), drop those index entries
    /// (so bake marks recompute), and delete CAFs no index references (orphans from older
    /// builds). Undecodable pre-engine-key indexes count as `legacyEngineID`. Launch-time only:
    /// nothing may be playing or baking.
    @discardableResult
    func purgeEngine(_ engineID: String) -> PurgeReport {
        var report = PurgeReport()
        guard let dirs = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return report
        }
        for dir in dirs {
            guard let articleID = UUID(uuidString: dir.lastPathComponent) else { continue }
            var touched = false
            var referenced = Set<String>()
            if var index = loadIndexLenient(for: articleID) {
                let doomed = index.paragraphs.filter { index.engine(of: $0) == engineID }
                if !doomed.isEmpty {
                    touched = true
                    report.articles += 1
                    report.paragraphs += doomed.count
                    for e in doomed {
                        let url = dir.appendingPathComponent(e.file)
                        report.bytes += FileSizes.allocatedBytes(at: url, fileManager: fileManager)
                        try? fileManager.removeItem(at: url)
                    }
                    let survivors = index.paragraphs.filter { index.engine(of: $0) != engineID }
                    if let first = survivors.first {
                        let eng = index.engine(of: first), voi = index.voice(of: first)
                        index.paragraphs = survivors
                        index = index.retargeted(engineID: eng, voiceID: voi)
                        try? JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
                    } else {
                        try? fileManager.removeItem(at: indexURL(for: articleID))
                        let chunks = dir.appendingPathComponent("chunks", isDirectory: true)
                        report.bytes += FileSizes.allocatedBytes(at: chunks, fileManager: fileManager)
                        try? fileManager.removeItem(at: chunks)
                    }
                    index.paragraphs = survivors
                }
                referenced = Set(index.paragraphs.map(\.file))
            }
            // Orphan CAFs (not in any index): never playable, safe to delete at launch.
            let files = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in files where name.hasSuffix(".caf") && !referenced.contains(name) {
                let url = dir.appendingPathComponent(name)
                report.orphanBytes += FileSizes.allocatedBytes(at: url, fileManager: fileManager)
                try? fileManager.removeItem(at: url)
                report.orphanFiles += 1
                touched = true
            }
            if touched { bakeProgress[articleID] = nil }
        }
        if report.paragraphs > 0 || report.orphanFiles > 0 { bumpContentRevision() }
        return report
    }

    /// `loadIndex`, but tolerates pre-engine-key files (no `engineID` → `legacyEngineID`).
    private func loadIndexLenient(for articleID: UUID) -> IndexFile? {
        if let index = try? loadIndex(for: articleID) { return index }
        guard let data = try? Data(contentsOf: indexURL(for: articleID)),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if obj["engineID"] == nil { obj["engineID"] = Self.legacyEngineID }
        if obj["voiceID"] == nil { obj["voiceID"] = "system" }
        if obj["createdAt"] == nil { obj["createdAt"] = 0 }
        if obj["paragraphs"] == nil { obj["paragraphs"] = [] }
        guard let patched = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return try? JSONDecoder().decode(IndexFile.self, from: patched)
    }
}
