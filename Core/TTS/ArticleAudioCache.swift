import Foundation
import Observation

@MainActor
@Observable
final class ArticleAudioCache {
    enum Status: Equatable {
        case missing
        case partial(ready: Int, total: Int)
        case ready(paragraphCount: Int)
    }

    struct IndexFile: Codable, Equatable {
        var engineID: String
        var voiceID: String
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

    /// Bumped when CAF index/files change so reading UI can refresh bake-ready marks.
    private(set) var contentRevision: UInt64 = 0
    let fileManager: FileManager
    /// Cache root (`Application Support/TTSCache` in the app; a temp dir in tests).
    let root: URL

    /// Each article's index, read from `index.json` once and kept current by every write (all of
    /// them go through this class). Holds only entries whose CAF exists with audio in it —
    /// checked when the index is loaded and when a unit is stored — so reads never touch the
    /// disk; they run on every scrubber redraw and per synth chunk. `.some(nil)`: no index.
    @ObservationIgnored private var indexes: [UUID: IndexFile?] = [:]
    #if DEBUG
    /// Tests: sees each step of a copy-on-write change (`ChangeStep`); throwing stops the change
    /// right there, as if the app died.
    @ObservationIgnored var faultHook: ((ChangeStep) throws -> Void)?
    #endif

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

    // MARK: Index (in memory)

    /// The article's index — usable entries only — or nil when it has none.
    func index(for articleID: UUID) -> IndexFile? {
        if let cached = indexes[articleID] { return cached }
        let loaded = readIndexFile(for: articleID).map { verified($0, articleID: articleID) }
        indexes[articleID] = .some(loaded)
        return loaded
    }

    /// Make `index` the article's index: in memory first (it describes the files as they are
    /// now, even if the write below fails), then `index.json`.
    func saveIndex(_ index: IndexFile, for articleID: UUID) throws {
        indexes[articleID] = .some(index)
        try JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
    }

    /// Make `index` the article's index on disk first, then in memory: the one commit point of a
    /// copy-on-write change (`ArticleAudioCache+Align`). If the write fails, memory still
    /// matches the disk.
    func publishIndex(_ index: IndexFile, for articleID: UUID) throws {
        try JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
        indexes[articleID] = .some(index)
    }

    /// Forget the in-memory copy (after rewriting the directory on disk); the next read reloads it.
    private func dropIndex(for articleID: UUID) {
        indexes.removeValue(forKey: articleID)
    }

    func readIndexFile(for articleID: UUID) -> IndexFile? {
        guard let data = try? Data(contentsOf: indexURL(for: articleID)) else { return nil }
        return try? JSONDecoder().decode(IndexFile.self, from: data)
    }

    /// `index` without entries whose CAF is missing or empty (e.g. the app died between the
    /// copy and the index write).
    private func verified(_ index: IndexFile, articleID: UUID) -> IndexFile {
        let dir = directory(for: articleID)
        var out = index
        out.paragraphs.removeAll { !isUsableAudioFile(dir.appendingPathComponent($0.file)) }
        return out
    }

    // MARK: Reads

    func status(for articleID: UUID, expectedParagraphs: Int? = nil) -> Status {
        guard let index = index(for: articleID) else { return .missing }
        let total = expectedParagraphs ?? index.paragraphs.count
        if total == 0 { return .missing }
        // Units in the index's (latest) engine/voice only; stale units of a previous voice don't count.
        let ready = index.paragraphs.filter { $0.engineID == nil && $0.voiceID == nil }.count
        if ready >= total { return .ready(paragraphCount: ready) }
        if ready == 0 { return .missing }
        return .partial(ready: ready, total: total)
    }

    /// CAF for this paragraph rendered with exactly this engine/voice (bake state, queue).
    func audioURL(articleID: UUID, paragraphIndex: Int, engineID: String, voiceID: String) -> URL? {
        guard let index = index(for: articleID),
              let entry = index.paragraphs.first(where: {
                  $0.index == paragraphIndex && index.matches($0, engineID: engineID, voiceID: voiceID)
              })
        else { return nil }
        return directory(for: articleID).appendingPathComponent(entry.file)
    }

    /// Playback: the current engine/voice's CAF, else a stale one (older voice/engine) until the
    /// paragraph is re-rendered — so a voice switch never makes baked audio unplayable.
    func playableAudioURL(articleID: UUID, paragraphIndex: Int, engineID: String, voiceID: String) -> URL? {
        if let exact = audioURL(articleID: articleID, paragraphIndex: paragraphIndex,
                                engineID: engineID, voiceID: voiceID) {
            return exact
        }
        guard let entry = entry(articleID: articleID, paragraphIndex: paragraphIndex) else { return nil }
        return directory(for: articleID).appendingPathComponent(entry.file)
    }

    /// Paragraph indices with a usable CAF for this engine/voice (stale units excluded).
    func readyIndices(
        articleID: UUID,
        paragraphCount: Int,
        engineID: String,
        voiceID: String
    ) -> Set<Int> {
        _ = contentRevision
        guard paragraphCount > 0, let index = index(for: articleID) else { return [] }
        return Set(index.paragraphs.lazy
            .filter { $0.index >= 0 && $0.index < paragraphCount && index.matches($0, engineID: engineID, voiceID: voiceID) }
            .map(\.index))
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

    /// "Audio ready": every paragraph `0..<paragraphCount` has a CAF rendered with exactly this
    /// engine and voice (stale units of another voice don't count).
    func isAudioReady(articleID: UUID, paragraphCount: Int, engineID: String, voiceID: String) -> Bool {
        paragraphCount > 0
            && readyIndices(articleID: articleID, paragraphCount: paragraphCount, engineID: engineID,
                            voiceID: voiceID).count == paragraphCount
    }

    /// Index entry for a ready paragraph (for chunk-boundary offsets).
    func entry(articleID: UUID, paragraphIndex: Int) -> IndexFile.ParagraphEntry? {
        index(for: articleID)?.paragraphs.first { $0.index == paragraphIndex }
    }

    // MARK: Writes

    func bumpContentRevision() {
        contentRevision &+= 1
    }

    func deleteAudio(for articleID: UUID) throws {
        let dir = directory(for: articleID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        indexes[articleID] = .some(nil)
        bumpContentRevision()
    }

    /// A paragraph's CAF: `p-NNNN.caf`.
    func paragraphFileURL(articleID: UUID, paragraphIndex: Int) -> URL {
        directory(for: articleID).appendingPathComponent(String(format: "p-%04d.caf", paragraphIndex))
    }

    /// File half of baking a paragraph, safe off the main actor: stitch `chunkURLs` beside
    /// `dest`, then rename it over `dest`. Never a write into `dest`: an old-voice CAF at that
    /// path may be playing right now, and its player keeps reading the old file. Then
    /// `recordParagraph` on the main actor.
    nonisolated static func stitchParagraph(_ chunkURLs: [URL], to dest: URL) throws -> ChunkAudioStitcher.Result {
        let fm = FileManager.default
        let dir = dest.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let staging = dir.appendingPathComponent(".stitch-" + dest.lastPathComponent)
        defer { try? fm.removeItem(at: staging) }
        let result = try ChunkAudioStitcher.stitch(chunkURLs, to: staging)
        guard hasAudio(at: staging) else { throw emptyAudioError(dest.lastPathComponent) }
        guard rename(staging.path, dest.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return result
    }

    /// Index half of storing a paragraph whose CAF is already at `paragraphFileURL`.
    func recordParagraph(
        articleID: UUID,
        paragraphIndex: Int,
        duration: TimeInterval,
        engineID: String,
        voiceID: String,
        textHash: String?,
        chunkDurations: [Double]?
    ) throws {
        // One voice per article: units of another engine/voice stay (stamped stale, still
        // playable) until their paragraph is re-rendered; this paragraph's old file was just
        // replaced. `finalizeVoiceSwitch` drops any leftovers once the article is complete.
        var entries = (index(for: articleID)?.retargeted(engineID: engineID, voiceID: voiceID).paragraphs ?? [])
            .filter { $0.index != paragraphIndex }
        entries.append(.init(
            index: paragraphIndex,
            file: paragraphFileURL(articleID: articleID, paragraphIndex: paragraphIndex).lastPathComponent,
            duration: duration,
            textHash: textHash,
            chunkDurations: chunkDurations
        ))
        entries.sort { $0.index < $1.index }

        let index = IndexFile(
            engineID: engineID,
            voiceID: voiceID,
            createdAt: Date(),
            paragraphs: entries
        )
        defer { bumpContentRevision() }
        try saveIndex(index, for: articleID)
    }

    private nonisolated static func emptyAudioError(_ unit: Any) -> NSError {
        NSError(domain: "ArticleAudioCache", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to store empty/tiny CAF at \(unit)"])
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

    /// Exists and holds more than a header: a CAF with audio in it (paragraph or synth chunk).
    func isUsableAudioFile(_ url: URL) -> Bool { Self.hasAudio(at: url) }

    nonisolated static func hasAudio(at url: URL) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else {
            return false
        }
        return size.intValue > 256
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

    /// Moves an article's audio under another key (Save of a legacy reader key, adopting a v1
    /// cache); `newKey` ends saved. When `newKey` has no directory, one rename moves it whole, so
    /// at every instant the audio is under one key or the other. Otherwise copy-on-write: the
    /// units `newKey` has none for (by paragraph) are copied in under new names, its index is
    /// saved, and only then is `oldKey`'s directory deleted.
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
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try fileManager.moveItem(at: src, to: dst)
            indexes[oldKey] = .some(nil)
            dropIndex(for: newKey)
            bumpContentRevision()
            try step(.movedDirectory)
            markSaved(cacheKey: newKey)
            return
        }
        let own = index(for: newKey)
        if let moving = index(for: oldKey) {
            var placed: [Int: AlignUnit] = [:]
            for unit in units(of: own, for: newKey, origin: .own) { placed[unit.entry.index] = unit }
            for unit in units(of: moving, for: oldKey, origin: .adopted) where placed[unit.entry.index] == nil {
                placed[unit.entry.index] = unit
            }
            if placed.values.contains(where: { $0.origin == .adopted }) {
                try publish(placed, for: newKey, engineID: moving.engineID, voiceID: moving.voiceID)
            }
        }
        try removeUnlisted(articleID: newKey, previous: own)
        markSaved(cacheKey: newKey)
        try deleteAudio(for: oldKey)
        try step(.removedFile)
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

// MARK: - One voice per article, retired engines, orphans

extension ArticleAudioCache {
    /// Engine id for index files that carry no `engineID`: only Chatterbox Nano (a retired
    /// engine, see `RetiredEngineCleanup`) wrote those.
    nonisolated static let legacyEngineID = "local.chatterbox-nano"

    /// Once every paragraph `0..<paragraphCount` has a CAF in `engineID`/`voiceID`, delete any
    /// remaining units of other voices/engines (e.g. indices past the end). Returns bytes freed.
    @discardableResult
    func finalizeVoiceSwitch(articleID: UUID, paragraphCount: Int, engineID: String, voiceID: String) -> Int64 {
        guard paragraphCount > 0, var index = index(for: articleID) else { return 0 }
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
        try? saveIndex(index, for: articleID)
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
            // Rewritten on disk from the raw file; the next read reloads (and verifies) it.
            if touched { dropIndex(for: articleID) }
        }
        if report.paragraphs > 0 || report.orphanFiles > 0 { bumpContentRevision() }
        return report
    }

    /// `index.json` as written (unverified), tolerating pre-engine-key files (no `engineID` →
    /// `legacyEngineID`).
    private func loadIndexLenient(for articleID: UUID) -> IndexFile? {
        if let index = readIndexFile(for: articleID) { return index }
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
