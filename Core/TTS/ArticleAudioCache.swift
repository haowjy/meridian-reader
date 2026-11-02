import Foundation
import Observation

@MainActor
@Observable
final class ArticleAudioCache {
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
            /// Engine / voice of this CAF when it differs from the index's `engineID`/`voiceID`
            /// ("stale"): only caches older builds wrote have them (a voice switch left the old
            /// voice's paragraphs in place until each was rendered again). Read so they never count
            /// or play in the index's voice; the launch deletes them once
            /// (`dropStaleVoiceParagraphs`). nil = the index's.
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
    /// How many times each article's index changed in this process (every write, delete, rekey,
    /// and a rewrite on disk that the next read reloads): the render queue keeps a job's missing
    /// paragraphs until its article's count moves (`indexChanges(of:)`).
    @ObservationIgnored private var indexChangeCounts: [UUID: UInt64] = [:]
    /// Each cache directory's `meta.json`, read once and kept current by every meta write and
    /// every move or delete of a directory (all of them go through this class): its kind is asked
    /// per chunk request, its owner by every walk of the cache (`entries()`). `.some(nil)`: no meta.
    @ObservationIgnored var metas: [UUID: CacheMeta?] = [:]
    /// Audio that waits for library work a launch couldn't finish (`LibraryStore.finishAudioWork`).
    /// Until a run of that work replaces it, the engine purges and the prune leave it alone, and
    /// its saved bake jobs aren't adopted: the work still needs what is there.
    @ObservationIgnored var held: Hold = .nothing

    enum Hold: Equatable {
        /// These pages' audio: a merge's source and destination, a page whose paragraphs were
        /// rebuilt.
        case articles(Set<UUID>)
        /// Every page's: the stored work couldn't be read, so any audio may be what it needs.
        case all

        static let nothing = Hold.articles([])

        func contains(_ articleID: UUID) -> Bool {
            switch self {
            case .articles(let keys): keys.contains(articleID)
            case .all: true
            }
        }
    }
    init(fileManager: FileManager = .default, root: URL) {
        self.fileManager = fileManager
        self.root = root
    }

    /// Keeps the cache out of backups (audio the app can render again); at launch, before
    /// anything renders, so every article directory is created inside a flagged root.
    @discardableResult
    func excludeFromBackup() -> Bool {
        BackupExclusion.exclude(root, fileManager: fileManager)
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

    /// Every article with audio of its own (an index in its live directory), by key (C134
    /// retention, the Prepared Audio list's From Listening section). Old voices aren't listed.
    func cachedArticleKeys() -> [UUID] {
        entries().filter(\.isLive).map(\.storageID).filter(hasCache(for:))
    }

    /// Bytes on disk of `articleID`'s audio.
    func bytes(for articleID: UUID) -> Int64 {
        FileSizes.allocatedBytes(at: directory(for: articleID), fileManager: fileManager)
    }

    /// The article has a cache directory, with or without an index.
    func hasDirectory(for articleID: UUID) -> Bool {
        fileManager.fileExists(atPath: directory(for: articleID).path)
    }

    // MARK: Index (in memory)

    /// The article's index — usable entries only — or nil when it has none.
    func index(for articleID: UUID) -> IndexFile? {
        if let cached = indexes[articleID] { return cached }
        let loaded = readIndexFile(for: articleID).map { verified($0, articleID: articleID) }
        indexes[articleID] = .some(loaded)
        return loaded
    }

    /// How many times `articleID`'s index changed in this process.
    func indexChanges(of articleID: UUID) -> UInt64 { indexChangeCounts[articleID, default: 0] }

    /// Every change of an article's index goes through here (a first read from disk doesn't
    /// change it). nil: the article has no index.
    private func setIndex(_ index: IndexFile?, for articleID: UUID) {
        indexes[articleID] = .some(index)
        indexChangeCounts[articleID, default: 0] &+= 1
    }

    /// Make `index` the article's index: in memory first (it describes the files as they are
    /// now, even if the write below fails), then `index.json`.
    func saveIndex(_ index: IndexFile, for articleID: UUID) throws {
        setIndex(index, for: articleID)
        try JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
    }

    /// Make `index` the article's index on disk first, then in memory: the one commit point of a
    /// copy-on-write change (`ArticleAudioCache+Align`). If the write fails, memory still
    /// matches the disk.
    func publishIndex(_ index: IndexFile, for articleID: UUID) throws {
        try JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
        setIndex(index, for: articleID)
    }

    /// Forget the in-memory copy (after rewriting the directory on disk); the next read reloads it.
    func dropIndex(for articleID: UUID) {
        indexes.removeValue(forKey: articleID)
        indexChangeCounts[articleID, default: 0] &+= 1
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

    /// CAF for this paragraph rendered with exactly this engine/voice (bake state, queue).
    func audioURL(articleID: UUID, paragraphIndex: Int, engineID: String, voiceID: String) -> URL? {
        guard let index = index(for: articleID),
              let entry = index.paragraphs.first(where: {
                  $0.index == paragraphIndex && index.matches($0, engineID: engineID, voiceID: voiceID)
              })
        else { return nil }
        return directory(for: articleID).appendingPathComponent(entry.file)
    }

    /// Playback: the CAF in the article's voice only (C138). An older voice's file waiting to be
    /// replaced never plays: an article never mixes voices; the paragraph renders in its voice.
    func playableAudioURL(articleID: UUID, paragraphIndex: Int, engineID: String, voiceID: String) -> URL? {
        audioURL(articleID: articleID, paragraphIndex: paragraphIndex, engineID: engineID, voiceID: voiceID)
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

    /// The one rule for "this paragraph still needs audio": of `paragraphs`, those with something
    /// to speak (a chunk plan with chunks, from `plans`) and no CAF in exactly this engine and
    /// voice (stale units of another voice don't count). A paragraph with nothing to speak (a bare
    /// "—") never gets audio, so it is never missing: an article is rendered once the rest is.
    /// The render queue, Prepared audio and staging the next chapter all
    /// ask this.
    func missingParagraphs(articleID: UUID, paragraphs: [String], engineID: String, voiceID: String,
                           plans: ChunkPlans) -> [Int] {
        let ready = readyIndices(articleID: articleID, paragraphCount: paragraphs.count, engineID: engineID, voiceID: voiceID)
        return paragraphs.indices.filter {
            !ready.contains($0) && plans.chunks(for: paragraphs[$0], engineID: engineID)?.isEmpty != true
        }
    }

    /// Index entry for a ready paragraph (for chunk-boundary offsets).
    func entry(articleID: UUID, paragraphIndex: Int) -> IndexFile.ParagraphEntry? {
        index(for: articleID)?.paragraphs.first { $0.index == paragraphIndex }
    }

    // MARK: Writes

    func bumpContentRevision() {
        contentRevision &+= 1
    }

    /// The directory and its chunk scratch (an article's live audio, or an old-voice entry by its
    /// storage id).
    func deleteAudio(for articleID: UUID) throws {
        let dir = directory(for: articleID)
        do {
            if fileManager.fileExists(atPath: dir.path) {
                try fileManager.removeItem(at: dir)
            }
        } catch {
            // A failed removal can have deleted some files: memory reloads what survived.
            forget([articleID])
            throw error
        }
        setIndex(nil, for: articleID)
        metas[articleID] = .some(nil)
        bumpContentRevision()
        removeChunkScratch(for: articleID)
    }

    /// A paragraph's CAF: `p-NNNN.caf`.
    func paragraphFileURL(articleID: UUID, paragraphIndex: Int) -> URL {
        directory(for: articleID).appendingPathComponent(String(format: "p-%04d.caf", paragraphIndex))
    }

    /// A name of its own to stitch paragraph `paragraphIndex` into, inside the chunk scratch of
    /// its text and voice: no index lists it and no alignment touches it, and the launch's
    /// scratch cleanup removes one an app died with.
    func stitchingURL(articleID: UUID, paragraphIndex: Int, textHash: String, voice: String) -> URL {
        chunkDirectory(articleID: articleID, paragraphIndex: paragraphIndex, textHash: textHash, voice: voice)
            .appendingPathComponent("paragraph-" + UUID().uuidString.prefix(8) + ".caf")
    }

    /// File half of baking a paragraph, safe off the main actor: stitch `chunkURLs` into
    /// `staging` (`stitchingURL`). `publishParagraph` then puts it in place on the main actor.
    nonisolated static func stitchParagraph(_ chunkURLs: [URL], to staging: URL) throws -> ChunkAudioStitcher.Result {
        let result = try ChunkAudioStitcher.stitch(chunkURLs, to: staging)
        guard hasAudio(at: staging) else {
            try? FileManager.default.removeItem(at: staging)
            throw emptyAudioError(staging.lastPathComponent)
        }
        return result
    }

    /// Index half of baking a paragraph: renames the stitched file over `p-NNNN.caf` and records
    /// it, in one main-actor step, so no alignment (`reconcile`, `rekeyCache`) runs between the
    /// file and its entry. A rename, never a write into `p-NNNN.caf`: a CAF there may be playing
    /// right now, and its player keeps reading the old file. One voice per live directory: when it
    /// holds another voice's audio, that becomes an old-voice entry first (`archiveLive`), and if
    /// that fails nothing is published.
    func publishParagraph(
        staged: URL,
        articleID: UUID,
        paragraphIndex: Int,
        duration: TimeInterval,
        engineID: String,
        voiceID: String,
        textHash: String,
        chunkDurations: [Double]?
    ) throws {
        if let held = audioVoice(of: articleID), held != CacheVoice(engineID: engineID, voiceID: voiceID) {
            try archiveLive(articleID)
        }
        try fileManager.createDirectory(at: directory(for: articleID), withIntermediateDirectories: true)
        let dest = paragraphFileURL(articleID: articleID, paragraphIndex: paragraphIndex)
        guard rename(staged.path, dest.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var entries = (index(for: articleID)?.paragraphs ?? []).filter { $0.index != paragraphIndex }
        entries.append(.init(index: paragraphIndex, file: dest.lastPathComponent, duration: duration,
                             textHash: textHash, chunkDurations: chunkDurations))
        entries.sort { $0.index < $1.index }
        defer { bumpContentRevision() }
        try saveIndex(IndexFile(engineID: engineID, voiceID: voiceID, createdAt: Date(), paragraphs: entries),
                      for: articleID)
    }

    private nonisolated static func emptyAudioError(_ unit: Any) -> NSError {
        NSError(domain: "ArticleAudioCache", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to store empty/tiny CAF at \(unit)"])
    }

    // MARK: - Synth chunk scratch (GlobalSynthQueue)

    /// `chunks/<article>/p-NNNN-<texthash>-<voice>/c-KK.caf` under the cache root — per-chunk
    /// renders of a paragraph that is still being built, in one cache voice. A call in flight when
    /// the voice changes writes into its own voice's folder, never where the new voice looks.
    /// Stitched into `p-NNNN.caf` when every chunk is present. Outside the article's directory, so
    /// only main-actor cache methods write there, and moving it (`archiveLive`) races no render.
    func chunkDirectory(articleID: UUID, paragraphIndex: Int, textHash: String, voice: String) -> URL {
        chunkScratch(for: articleID)
            .appendingPathComponent(Self.chunkFolderPrefix(paragraphIndex, textHash) + voice, isDirectory: true)
    }

    private var chunkScratchRoot: URL { root.appendingPathComponent("chunks", isDirectory: true) }

    private func chunkScratch(for articleID: UUID) -> URL {
        chunkScratchRoot.appendingPathComponent(articleID.uuidString, isDirectory: true)
    }

    func chunkURL(articleID: UUID, paragraphIndex: Int, textHash: String, voice: String, chunk: Int) -> URL {
        chunkDirectory(articleID: articleID, paragraphIndex: paragraphIndex, textHash: textHash, voice: voice)
            .appendingPathComponent(String(format: "c-%02d.caf", chunk))
    }

    /// The part of a chunk folder's name that names the paragraph and its text: `p-NNNN-<texthash>-`.
    private static func chunkFolderPrefix(_ paragraphIndex: Int, _ textHash: String) -> String {
        String(format: "p-%04d-", paragraphIndex) + textHash + "-"
    }

    /// Drop chunk scratch for one article (never while it is the live playback session).
    func removeChunkScratch(for articleID: UUID) {
        try? fileManager.removeItem(at: chunkScratch(for: articleID))
    }

    /// Drop chunk scratch for one article except the dirs that still match `paragraphs`
    /// (same index + text hash, any voice): those hold finished chunks of a paragraph the queue
    /// is baking right now. Wiping them made the worker synthesize the same chunks again —
    /// extra model calls, each one more exposure to an engine crash.
    func removeChunkScratch(for articleID: UUID, keepingCurrent paragraphs: [String]) {
        let dir = chunkScratch(for: articleID)
        guard let subdirs = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        let keep = Set(paragraphs.indices.map { Self.chunkFolderPrefix($0, ArticleIdentity.paragraphHash(paragraphs[$0])) })
        for name in subdirs where !keep.contains(where: name.hasPrefix) {
            try? fileManager.removeItem(at: dir.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// Launch-time cleanup: nothing is playing yet, so all chunk scratch is disposable, the
    /// scratch older builds kept inside each article's directory included.
    func removeAllChunkScratch() {
        try? fileManager.removeItem(at: chunkScratchRoot)
        for entry in entries() {
            try? fileManager.removeItem(at: directory(for: entry.storageID).appendingPathComponent("chunks", isDirectory: true))
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

// MARK: - Ephemeral meta, rekey, prune

extension ArticleAudioCache {
    struct CacheMeta: Codable, Equatable {
        enum Kind: String, Codable { case ephemeral, saved }
        var kind: Kind
        var canonicalURL: String?
        var createdAt: Date
        var lastAccessAt: Date
        /// An old-voice entry's article: the key whose audio this was before its voice changed
        /// (`archiveLive`). nil in an article's own (live) directory.
        var voiceOf: UUID? = nil
    }

    private func metaURL(for articleID: UUID) -> URL {
        directory(for: articleID).appendingPathComponent("meta.json")
    }

    /// `meta.json` as it is on disk.
    func loadMeta(for articleID: UUID) -> CacheMeta? {
        guard let data = try? Data(contentsOf: metaURL(for: articleID)) else { return nil }
        return try? JSONDecoder().decode(CacheMeta.self, from: data)
    }

    /// `meta.json`, from memory after the first read.
    func meta(for articleID: UUID) -> CacheMeta? {
        if let meta = metas[articleID] { return meta }
        let meta = loadMeta(for: articleID)
        metas[articleID] = .some(meta)
        return meta
    }

    /// The article's audio is on the ephemeral TTL (an unsaved page's).
    func isEphemeral(_ articleID: UUID) -> Bool {
        meta(for: articleID)?.kind == .ephemeral
    }

    /// Writes `meta.json`; on failure memory reads the disk again next time.
    func writeMeta(_ meta: CacheMeta, for articleID: UUID) throws {
        do {
            try JSONEncoder().encode(meta).write(to: metaURL(for: articleID), options: .atomic)
            metas[articleID] = .some(meta)
        } catch {
            metas[articleID] = nil
            throw error
        }
    }

    /// The article's live directory goes on the ephemeral TTL, created if missing.
    func markEphemeral(cacheKey: UUID, canonicalURL: String? = nil, lastAccess: Date = Date()) throws {
        try fileManager.createDirectory(at: directory(for: cacheKey), withIntermediateDirectories: true)
        let existing = loadMeta(for: cacheKey)
        try writeMeta(CacheMeta(kind: .ephemeral, canonicalURL: canonicalURL ?? existing?.canonicalURL,
                                createdAt: existing?.createdAt ?? Date(), lastAccessAt: lastAccess),
                      for: cacheKey)
    }

    /// The article's live directory, if it has one, is a saved page's.
    func markSaved(cacheKey: UUID) throws {
        guard fileManager.fileExists(atPath: directory(for: cacheKey).path) else { return }
        let existing = loadMeta(for: cacheKey)
        try writeMeta(CacheMeta(kind: .saved, canonicalURL: existing?.canonicalURL,
                                createdAt: existing?.createdAt ?? Date(), lastAccessAt: Date()),
                      for: cacheKey)
    }

    /// Installs a recording (a folder holding `index.json` and its CAFs, as this cache wrote them)
    /// as the saved audio of `key`, then aligns it with `paragraphs`, which drops any paragraph
    /// whose text is not the one recorded. Only into a key with no audio, and only a recording
    /// in `voice`. False when it is refused or fails, leaving nothing behind.
    func install(recording: URL, as key: UUID, voice: CacheVoice?, paragraphs: [String]) -> Bool {
        guard let voice, !hasCache(for: key),
              let data = try? Data(contentsOf: recording.appendingPathComponent("index.json")),
              let recorded = try? JSONDecoder().decode(IndexFile.self, from: data),
              recorded.engineID == voice.engineID, recorded.voiceID == voice.voiceID else { return false }
        // Copied beside, then renamed into place: a kill mid-copy leaves no half-installed folder.
        // `entries()` skips a name that is not a key's.
        let staging = root.appendingPathComponent(".install", isDirectory: true)
        do {
            try? fileManager.removeItem(at: staging)
            try fileManager.copyItem(at: recording, to: staging)
            try? fileManager.removeItem(at: directory(for: key))
            try fileManager.moveItem(at: staging, to: directory(for: key))
            forget([key])
            try reconcile(articleID: key, paragraphs: paragraphs)
            try markSaved(cacheKey: key)
            return true
        } catch {
            try? fileManager.removeItem(at: staging)
            try? deleteAudio(for: key)
            return false
        }
    }

    /// Moves an article's audio under another key (Save of a legacy reader key, adopting a v1
    /// cache); `newKey` ends saved. First the old voices of `oldKey` become `newKey`'s, and
    /// `oldKey`'s audio becomes an old-voice entry of `newKey` when it isn't in `voice` (the voice
    /// `newKey` renders in; `prepareMerge`). When `newKey` has no directory, one rename moves it
    /// whole, so at every instant the audio is under one key or the other. Otherwise
    /// copy-on-write: the units `newKey` has none for (by paragraph) are copied in under new
    /// names, its index is saved, and only then is `oldKey`'s directory deleted.
    func rekeyCache(from oldKey: UUID, to newKey: UUID, voice: CacheVoice?) throws {
        guard oldKey != newKey else {
            try markSaved(cacheKey: newKey)
            return
        }
        let src = directory(for: oldKey)
        let dst = directory(for: newKey)
        guard try prepareMerge(from: oldKey, into: newKey, voice: voice),
              fileManager.fileExists(atPath: src.path) else {
            try markSaved(cacheKey: newKey)
            return
        }
        if !fileManager.fileExists(atPath: dst.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            defer { forget([oldKey, newKey]) }
            try fileManager.moveItem(at: src, to: dst)
            try? fileManager.moveItem(at: chunkScratch(for: oldKey), to: chunkScratch(for: newKey))
            try markSaved(cacheKey: newKey)
            return
        }
        try fillMissing(newKey, from: oldKey)
        try markSaved(cacheKey: newKey)
        try deleteAudio(for: oldKey)
    }

    /// Prune ephemeral caches older than `maxAge` or when total ephemeral size exceeds `maxBytes`:
    /// unsaved pages' audio and old-voice entries alike, a whole directory at a time. Saved caches
    /// are never pruned here, nor held ones (`held`, resolved through the owner: a hold on an
    /// article holds its old voices too). Choice: survive leaving Reader + app restart; TTL by
    /// age/size.
    @discardableResult
    func pruneEphemeral(
        maxAge: TimeInterval = 7 * 24 * 60 * 60,
        maxBytes: Int64 = 2 * 1024 * 1024 * 1024
    ) -> (removed: Int, freedBytes: Int64) {
        struct Entry {
            var id: UUID
            var url: URL
            var meta: CacheMeta
            var bytes: Int64
        }

        var ephemeral: [Entry] = []
        let now = Date()
        for entry in entries() where entry.kind == .ephemeral && !held.contains(entry.owner) {
            guard let meta = meta(for: entry.storageID) else { continue }
            let dir = directory(for: entry.storageID)
            ephemeral.append(Entry(id: entry.storageID, url: dir, meta: meta, bytes: directorySize(dir)))
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

// MARK: - Retired engines, voice key changes, orphans

extension ArticleAudioCache {
    /// Engine id for index files that carry no `engineID`: only Chatterbox Nano (a retired
    /// engine, see `RetiredEngineCleanup`) wrote those.
    nonisolated static let legacyEngineID = "local.chatterbox-nano"

    struct PurgeReport: Equatable {
        var articles = 0
        var paragraphs = 0
        var bytes: Int64 = 0
        var orphanFiles = 0
        var orphanBytes: Int64 = 0
        /// Articles left alone because they are held (`held`): purge again once nothing is.
        var held = 0
    }

    /// Delete every cached unit rendered by `engineID` (all articles), drop those index entries
    /// (so bake marks recompute), and delete CAFs no index references (orphans from older
    /// builds). Undecodable pre-engine-key indexes count as `legacyEngineID`. Held articles
    /// (`held`) are left alone and counted. Old-voice entries are walked like live directories.
    /// Launch-time only: nothing may be playing or baking.
    @discardableResult
    func purgeEngine(_ engineID: String) -> PurgeReport {
        var report = PurgeReport()
        for entry in entries() {
            let articleID = entry.storageID
            let dir = directory(for: articleID)
            if held.contains(entry.owner) {
                report.held += 1
                continue
            }
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

    /// Rewrite cache voice keys in every index, for a voice library whose key format changed
    /// (`rename`: the new key, nil to keep it). Only the indexes change; the files stay. Old-voice
    /// entries too: their voice is read from their index, so they stay findable. Launch-time only,
    /// like `purgeEngine`. `complete`: the cache was listed and every index read, and each one
    /// that needed it written.
    func renameVoices(_ rename: (String) -> String?) -> (articles: Int, complete: Bool) {
        var articles = 0
        var complete = true
        guard (try? fileManager.contentsOfDirectory(atPath: root.path)) != nil else {
            return (0, !fileManager.fileExists(atPath: root.path))
        }
        for articleID in entries().map(\.storageID) where hasCache(for: articleID) {
            // A file that can't be read now (locked before first unlock) is retried next launch;
            // one that reads but doesn't decode never will, and no read path can use it.
            guard let data = try? Data(contentsOf: indexURL(for: articleID)) else { complete = false; continue }
            guard var index = try? JSONDecoder().decode(IndexFile.self, from: data) else { continue }
            let before = index
            index.voiceID = rename(index.voiceID) ?? index.voiceID
            for i in index.paragraphs.indices {
                if let voice = index.paragraphs[i].voiceID { index.paragraphs[i].voiceID = rename(voice) ?? voice }
            }
            guard index != before else { continue }
            do {
                try JSONEncoder().encode(index).write(to: indexURL(for: articleID), options: .atomic)
                articles += 1
            } catch {
                complete = false
            }
            dropIndex(for: articleID)
        }
        if articles > 0 { bumpContentRevision() }
        return (articles, complete)
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
