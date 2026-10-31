import Foundation

// MARK: - Old voices: an article's audio in a voice it no longer uses

/// An article's own audio is in its **live directory**, named by its key, in one voice. When it
/// changes voice, the old voice's audio becomes an **old-voice entry**: a directory with a random
/// name whose `meta.json` names its article (`voiceOf`), on the ephemeral TTL from the moment it
/// was left, so `pruneEphemeral` ages it out like an unsaved page's audio. Switching back makes
/// it the article's live audio again (`settleVoice`). An entry's voice is read from its index, so
/// the launch's voice key migrations (`renameVoices`) keep it findable.
///
/// Audio enters a live directory only through `publishParagraph`, which archives another voice
/// there first, and through merges, which never put a second voice in one (`prepareMerge`). So no
/// live directory mixes voices, finished change or not, and readers already check the voice.
///
/// Every operation that moves, deletes or creates a directory keeps the in-memory indexes and
/// metadata true itself before it returns, on success and on failure (`forget`): callers read
/// the index right after (a publish right after `archiveLive`), and a stale one would list the
/// old voice's paragraphs, whose files have moved, as the article's.
extension ArticleAudioCache {
    /// The voice audio is filed under: its engine and its cache voice key.
    struct CacheVoice: Hashable {
        var engineID: String
        var voiceID: String
    }

    /// A top-level cache directory: an article's live directory or an old-voice entry.
    struct CacheEntry: Equatable {
        /// The directory's name.
        let storageID: UUID
        /// The article whose audio it is: its meta's `voiceOf`, else its own name.
        let owner: UUID
        let kind: CacheMeta.Kind?
        /// The article's own directory, by name, whatever its metadata says (a `voiceOf` naming
        /// itself is an archive left part way, which the voice record finishes).
        var isLive: Bool { storageID == owner }
    }

    /// Every directory in the cache root: the one walk every path that walks audio uses.
    func entries() -> [CacheEntry] { scanEntries(meta(for:)) }

    private func scanEntries(_ metaOf: (UUID) -> CacheMeta?) -> [CacheEntry] {
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap(UUID.init(uuidString:)).compactMap { id in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory(for: id).path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            let meta = metaOf(id)
            return CacheEntry(storageID: id, owner: meta?.voiceOf ?? id, kind: meta?.kind)
        }
    }

    /// The voice of the audio a directory holds (its index's); nil when it holds none.
    func audioVoice(of storageID: UUID) -> CacheVoice? {
        guard let index = index(for: storageID), !index.paragraphs.isEmpty else { return nil }
        return CacheVoice(engineID: index.engineID, voiceID: index.voiceID)
    }

    /// `owner`'s old-voice entries, never its live directory.
    func oldVoices(of owner: UUID) -> [CacheEntry] {
        entries().filter { !$0.isLive && $0.owner == owner }
    }

    /// `owner`'s old-voice entry in `voice` (other than `except`). Of two in one voice the more
    /// recently left is kept and the other deleted.
    func oldVoice(of owner: UUID, in voice: CacheVoice, except: UUID? = nil) throws -> CacheEntry? {
        let matching = oldVoices(of: owner)
            .filter { $0.storageID != except && audioVoice(of: $0.storageID) == voice }
            .sorted { leftAt($0.storageID) > leftAt($1.storageID) }
        for extra in matching.dropFirst() { try deleteAudio(for: extra.storageID) }
        return matching.first
    }

    private func leftAt(_ storageID: UUID) -> Date { meta(for: storageID)?.lastAccessAt ?? .distantPast }

    /// *Clear Audio* and deleting the article: its old voices go too.
    func deleteOldVoices(of owner: UUID) throws {
        for entry in oldVoices(of: owner) { try deleteAudio(for: entry.storageID) }
    }

    /// Drops what memory holds of these directories (index, metadata) after they moved or were
    /// rewritten on disk; the next read loads them again.
    func forget(_ ids: [UUID]) {
        for id in ids {
            dropIndex(for: id)
            metas[id] = nil
        }
        bumpContentRevision()
    }

    // MARK: Archiving

    /// The live directory's voice becomes an old-voice entry of `key`, and the live directory is
    /// created again, empty, with its metadata (no `voiceOf`), so an unsaved page keeps its place
    /// on the ephemeral TTL. Nothing to do when it holds no audio.
    func archiveLive(_ key: UUID) throws {
        let live = loadMeta(for: key)
        guard try retire(key, to: key) != nil else { return }
        defer { forget([key]) }
        try fileManager.createDirectory(at: directory(for: key), withIntermediateDirectories: true)
        if var live {
            live.voiceOf = nil
            try writeMeta(live, for: key)
        }
    }

    /// `storageID`'s audio becomes an old-voice entry of `owner`: an entry of `owner` in the same
    /// voice goes (this audio is newer), the ownership is written to its metadata, and only then
    /// does the directory take a random name, so a directory never moves without it. Returns the
    /// entry's name; nil when the directory holds no audio.
    @discardableResult
    private func retire(_ storageID: UUID, to owner: UUID) throws -> UUID? {
        guard let voice = audioVoice(of: storageID) else { return nil }
        let id = UUID()
        defer { forget([storageID, id]) }
        if let existing = try oldVoice(of: owner, in: voice, except: storageID) {
            try deleteAudio(for: existing.storageID)
        }
        let old = loadMeta(for: storageID)
        try writeMeta(CacheMeta(kind: .ephemeral, canonicalURL: old?.canonicalURL, createdAt: old?.createdAt ?? Date(),
                                lastAccessAt: Date(), voiceOf: owner),
                      for: storageID)
        try fileManager.moveItem(at: directory(for: storageID), to: directory(for: id))
        return id
    }

    // MARK: A voice change

    /// From any state a voice change can leave, to the invariant for article `key` speaking in
    /// `voice`: its live directory holds `voice`'s audio or none, with live metadata (no `voiceOf`,
    /// `kind`); every other voice of it is in an old-voice entry, at most one per voice; no entry
    /// holds `voice`. Each step is one write, rename or delete, so running it again after a failure
    /// or a process death finishes it; on a settled article it changes nothing. `paragraphs`: the
    /// article's listen paragraphs, which a restored voice is aligned to first. `voice` nil (no
    /// registered engine speaks the article's voice): only the metadata is settled.
    func settleVoice(_ key: UUID, in voice: CacheVoice?, paragraphs: [String], kind: CacheMeta.Kind,
                     chunkPlan: ((String, String) -> [String]?)?) throws {
        var carried = loadMeta(for: key)
        if let voice {
            if let live = audioVoice(of: key), live != voice { try archiveLive(key) }
            if let entry = try oldVoice(of: key, in: voice) {
                carried = carried ?? loadMeta(for: entry.storageID)
                if paragraphs.isEmpty {
                    try deleteAudio(for: entry.storageID) // nothing to align it to: renders as new
                } else {
                    // Aligned while still an entry: a paragraph whose text changed while the voice
                    // was away never plays. Its commit point is the entry's index.
                    try reconcile(articleID: entry.storageID, paragraphs: paragraphs, chunkPlan: chunkPlan)
                    if audioVoice(of: key) == nil {
                        // The live directory holds at most its metadata (scratch is elsewhere).
                        defer { forget([key, entry.storageID]) }
                        if hasDirectory(for: key) { try fileManager.removeItem(at: directory(for: key)) }
                        try fileManager.moveItem(at: directory(for: entry.storageID), to: directory(for: key))
                    } else {
                        // Published in `voice` after an earlier run failed: fill in what it lacks.
                        try fillMissing(key, from: entry.storageID)
                        try deleteAudio(for: entry.storageID)
                    }
                }
            }
        }
        if !hasDirectory(for: key) {
            guard !oldVoices(of: key).isEmpty else { return } // no audio of it at all
            defer { forget([key]) }
            try fileManager.createDirectory(at: directory(for: key), withIntermediateDirectories: true)
        }
        let meta = loadMeta(for: key)
        if meta == nil || meta?.voiceOf != nil || meta?.kind != kind {
            try writeMeta(CacheMeta(kind: kind, canonicalURL: meta?.canonicalURL ?? carried?.canonicalURL,
                                    createdAt: meta?.createdAt ?? carried?.createdAt ?? Date(), lastAccessAt: Date()),
                          for: key)
        }
    }

    /// The postcondition of `settleVoice`, read from disk.
    func isVoiceSettled(_ key: UUID, in voice: CacheVoice?, kind: CacheMeta.Kind) -> Bool {
        let old = scanEntries(loadMeta(for:)).filter { !$0.isLive && $0.owner == key }
        guard hasDirectory(for: key) else { return old.isEmpty }
        guard let meta = loadMeta(for: key), meta.voiceOf == nil, meta.kind == kind else { return false }
        guard let voice else { return true }
        func diskVoice(_ id: UUID) -> CacheVoice? {
            readIndexFile(for: id).flatMap { $0.paragraphs.isEmpty ? nil : CacheVoice(engineID: $0.engineID, voiceID: $0.voiceID) }
        }
        let oldVoices = old.compactMap { diskVoice($0.storageID) }
        return (diskVoice(key) ?? voice) == voice && !oldVoices.contains(voice) && Set(oldVoices).count == oldVoices.count
    }

    // MARK: Merges

    /// Before `source`'s audio joins `key`'s (a merge, Save under an older key): `source`'s old
    /// voices become `key`'s (per voice, the more recently left wins), and no merge puts a second
    /// voice in a live directory. `source`'s live audio in another voice than `key` renders in
    /// (`voice`; unknown: `key`'s own audio's, else the source's) becomes `key`'s old-voice entry,
    /// and false says nothing is left to merge; `key`'s live audio in another voice than the
    /// merging audio is archived first.
    func prepareMerge(from source: UUID, into key: UUID, voice: CacheVoice?) throws -> Bool {
        for entry in oldVoices(of: source) { try giveOldVoice(entry.storageID, to: key) }
        guard let moving = audioVoice(of: source) else { return true }
        let keeping = audioVoice(of: key)
        guard moving == voice ?? keeping ?? moving else {
            try retire(source, to: key)
            return false
        }
        if let keeping, keeping != moving { try archiveLive(key) }
        return true
    }

    private func giveOldVoice(_ id: UUID, to owner: UUID) throws {
        defer { forget([id]) }
        guard var moved = loadMeta(for: id) else { return }
        if let voice = audioVoice(of: id), let other = try oldVoice(of: owner, in: voice, except: id) {
            if leftAt(other.storageID) >= moved.lastAccessAt { return try deleteAudio(for: id) }
            try deleteAudio(for: other.storageID)
        }
        moved.voiceOf = owner
        try writeMeta(moved, for: id)
    }

    /// Copy-on-write: the units `key` has none for (by paragraph) are copied in from `source`
    /// under new names and `key`'s index is saved; `source` is left as it was. Both in one voice
    /// (`prepareMerge`).
    func fillMissing(_ key: UUID, from source: UUID) throws {
        let own = index(for: key)
        if let moving = index(for: source) {
            var placed: [Int: AlignUnit] = [:]
            for unit in units(of: own, for: key, origin: .own) { placed[unit.entry.index] = unit }
            for unit in units(of: moving, for: source, origin: .adopted) where placed[unit.entry.index] == nil {
                placed[unit.entry.index] = unit
            }
            if placed.values.contains(where: { $0.origin == .adopted }) {
                try publish(placed, for: key, engineID: moving.engineID, voiceID: moving.voiceID)
            }
        }
        try removeUnlisted(articleID: key, previous: own)
    }

    // MARK: Older builds' caches

    /// Once, at launch: paragraphs older builds left in a voice other than their index's (a voice
    /// switch not yet rendered again; they never counted or played) are deleted, as that build
    /// deleted them once the new voice was whole. Held audio waits. `complete`: nothing held was
    /// skipped and every index that needed it was written.
    func dropStaleVoiceParagraphs() -> (articles: Int, complete: Bool) {
        var articles = 0
        var complete = true
        for entry in entries() {
            let id = entry.storageID
            guard var index = readIndexFile(for: id),
                  index.paragraphs.contains(where: { $0.engineID != nil || $0.voiceID != nil }) else { continue }
            guard !held.contains(entry.owner) else {
                complete = false
                continue
            }
            let written = index
            let stale = written.paragraphs.filter { !written.matches($0, engineID: written.engineID, voiceID: written.voiceID) }
            index.paragraphs = written.paragraphs
                .filter { written.matches($0, engineID: written.engineID, voiceID: written.voiceID) }
                .map { var e = $0; e.engineID = nil; e.voiceID = nil; return e }
            do { try publishIndex(index, for: id) } catch {
                complete = false
                continue
            }
            let kept = Set(index.paragraphs.map(\.file))
            for e in stale where !kept.contains(e.file) {
                try? fileManager.removeItem(at: directory(for: id).appendingPathComponent(e.file))
            }
            dropIndex(for: id)
            articles += 1
        }
        if articles > 0 { bumpContentRevision() }
        return (articles, complete)
    }
}
