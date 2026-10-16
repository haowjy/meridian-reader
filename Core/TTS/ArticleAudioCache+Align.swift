import Foundation

// MARK: - Aligning audio with an article's paragraphs (identity v2, layout v3), copy-on-write

/// A change to an article's audio never removes or renames a CAF its saved `index.json` lists
/// before the index that replaces it is saved. New CAFs (moved units, slices, units taken from a
/// merged article) are written first under new names, the new index is saved in one atomic
/// write (`publishIndex`), and only then are the CAFs it no longer lists deleted. An app that
/// dies at any step leaves an index whose every CAF exists, so a cold load drops nothing, and
/// running the change again finishes it. `p-NNNN.caf` is where the render queue writes paragraph
/// NNNN, so a unit that lands on another paragraph is copied to an `m-` name; `s-` names are
/// slices. Only these changes write `m-` and `s-` files, so any of them no index lists is a
/// leftover of an interrupted change and is deleted.
extension ArticleAudioCache {
    struct ReconcileResult: Equatable {
        /// Units still on a paragraph with their text.
        var kept = 0
        /// Units moved to the nearest free paragraph with their text.
        var remapped = 0
        /// Units whose text no longer exists, or whose paragraph already has a unit.
        var dropped = 0
        /// Unhashed (pre-v2) units kept on their slot.
        var unverified = 0
        /// Units taken from the merged article (`adopting`).
        var adopted = 0
        /// Old CAFs whose paragraph is now several (layout v3).
        var splitParagraphs = 0
        /// New paragraphs cut out of such a CAF (their chunk plan lined up with its chunks).
        var sliced = 0
        /// New paragraphs of a split one whose chunks didn't line up (they re-render).
        var misaligned = 0
        var changed: Bool { remapped > 0 || dropped > 0 || adopted > 0 || sliced > 0 }
    }

    /// A CAF taking part in a change: its entry, its engine and voice, and where the file is now.
    struct AlignUnit {
        enum Origin { case own, slice, adopted }
        var entry: IndexFile.ParagraphEntry
        var engineID: String
        var voiceID: String
        var url: URL
        /// `own` and `slice` CAFs are in the article's directory: one that stays on its paragraph
        /// keeps its file.
        var origin: Origin
    }

    /// Stamp entries written before v2 (no `textHash`) with the text they were rendered from.
    /// Only call with paragraphs known to match the cache (e.g. the saved copy's stored blocks,
    /// or content whose legacy v1 key equalled this cache dir).
    func stampMissingHashes(articleID: UUID, paragraphs: [String]) throws {
        guard var index = index(for: articleID) else { return }
        var changed = false
        for i in index.paragraphs.indices where index.paragraphs[i].textHash == nil {
            let p = index.paragraphs[i].index
            guard paragraphs.indices.contains(p) else { continue }
            index.paragraphs[i].textHash = ArticleIdentity.paragraphHash(paragraphs[p])
            changed = true
        }
        guard changed else { return }
        try publishIndex(index, for: articleID)
    }

    /// Aligns the article's audio with `paragraphs`, its current listen blocks: a unit on a
    /// paragraph with its text stays; a unit whose paragraph shifted moves to the nearest free
    /// paragraph with its text; a paragraph split since it was rendered keeps the pieces whose
    /// chunks line up with the old render (`slices`; `chunkPlan` is the render queue's plan, nil
    /// cuts nothing); the rest is dropped. Unhashed legacy units keep their slot. `adopting`: a
    /// merged article whose audio fills the paragraphs this one has no unit for, the same way;
    /// its directory is deleted once this article's index is saved. Copy-on-write (above): a
    /// failure throws and leaves the last saved index usable.
    @discardableResult
    func reconcile(articleID: UUID, paragraphs: [String], adopting source: UUID? = nil,
                   chunkPlan: ((String, String) -> [String]?)? = nil) throws -> ReconcileResult {
        var result = ReconcileResult()
        let source = source == articleID ? nil : source
        let own = index(for: articleID)
        let merged = source.flatMap { index(for: $0) }
        var units = self.units(of: own, for: articleID, origin: .own)
        if let source { units += self.units(of: merged, for: source, origin: .adopted) }
        var placed: [Int: AlignUnit] = [:]
        if !units.isEmpty {
            let slices = try self.slices(of: units, paragraphs: paragraphs, into: directory(for: articleID),
                                         chunkPlan: chunkPlan, &result)
            placed = place(slices + units, on: paragraphs, &result)
        }
        let unchanged = placed.count == (own?.paragraphs.count ?? 0)
            && placed.allSatisfy { $0.value.origin == .own && $0.value.entry.index == $0.key }
        // The saved index can list CAFs the loaded one left out (missing or empty files).
        if let base = own ?? merged, !unchanged || readIndexFile(for: articleID) != own {
            try publish(placed, for: articleID, engineID: base.engineID, voiceID: base.voiceID)
        }
        if let source, hasDirectory(for: source) {
            if merged != nil { markSaved(cacheKey: articleID) }
            try deleteAudio(for: source)
        }
        try removeUnlisted(articleID: articleID, previous: own)
        return result
    }

    /// The postcondition of `reconcile`, read from disk: the saved index lists only usable CAFs,
    /// each on a paragraph with its text (an unhashed one on any paragraph). An unreadable index
    /// holds no usable audio, so it passes.
    func isAligned(articleID: UUID, paragraphs: [String]) -> Bool {
        guard let index = readIndexFile(for: articleID) else { return true }
        let dir = directory(for: articleID)
        return index.paragraphs.allSatisfy { e in
            guard paragraphs.indices.contains(e.index), isUsableAudioFile(dir.appendingPathComponent(e.file)) else {
                return false
            }
            return e.textHash.map { $0 == ArticleIdentity.paragraphHash(paragraphs[e.index]) } ?? true
        }
    }

    func units(of index: IndexFile?, for articleID: UUID, origin: AlignUnit.Origin) -> [AlignUnit] {
        guard let index else { return [] }
        let dir = directory(for: articleID)
        return index.paragraphs.map {
            AlignUnit(entry: $0, engineID: index.engine(of: $0), voiceID: index.voice(of: $0),
                      url: dir.appendingPathComponent($0.file), origin: origin)
        }
    }

    /// Which unit ends up on each paragraph. In order: a unit on a paragraph with its text keeps
    /// it (the first one wins), an unhashed unit keeps its slot; then the others move to the
    /// nearest free paragraph with their text, or are dropped.
    private func place(_ units: [AlignUnit], on paragraphs: [String], _ result: inout ReconcileResult) -> [Int: AlignUnit] {
        let hashes = paragraphs.map(ArticleIdentity.paragraphHash)
        var targets: [String: [Int]] = [:]
        for (i, h) in hashes.enumerated() { targets[h, default: []].append(i) }
        var placed: [Int: AlignUnit] = [:]
        func count(_ unit: AlignUnit, moved: Bool) {
            switch unit.origin {
            case .adopted: result.adopted += 1
            case .slice: break
            case .own: if moved { result.remapped += 1 } else { result.kept += 1 }
            }
        }
        var rest: [AlignUnit] = []
        for unit in units {
            let i = unit.entry.index
            guard let hash = unit.entry.textHash else {
                if hashes.indices.contains(i), placed[i] == nil {
                    placed[i] = unit
                    result.unverified += 1
                } else {
                    result.dropped += 1
                }
                continue
            }
            if hashes.indices.contains(i), hashes[i] == hash, placed[i] == nil {
                placed[i] = unit
                count(unit, moved: false)
            } else {
                rest.append(unit)
            }
        }
        for unit in rest {
            let free = (targets[unit.entry.textHash ?? ""] ?? []).filter { placed[$0] == nil }
            if let target = free.min(by: { abs($0 - unit.entry.index) < abs($1 - unit.entry.index) }) {
                placed[target] = unit
                count(unit, moved: true)
            } else {
                result.dropped += 1
            }
        }
        return placed
    }

    /// Copies each placed unit that isn't already this article's file on that paragraph in under
    /// a new `m-` name, then saves the index listing them all: the commit point.
    func publish(_ placed: [Int: AlignUnit], for articleID: UUID, engineID: String, voiceID: String) throws {
        let dir = directory(for: articleID)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var entries: [IndexFile.ParagraphEntry] = []
        for (paragraph, unit) in placed.sorted(by: { $0.key < $1.key }) {
            var entry = unit.entry
            if unit.origin == .adopted || entry.index != paragraph {
                let name = String(format: "m-%04d-", paragraph) + UUID().uuidString.prefix(8) + ".caf"
                try fileManager.copyItem(at: unit.url, to: dir.appendingPathComponent(name))
                entry.file = name
            }
            entry.index = paragraph
            let same = unit.engineID == engineID && unit.voiceID == voiceID
            entry.engineID = same ? nil : unit.engineID
            entry.voiceID = same ? nil : unit.voiceID
            entries.append(entry)
        }
        try publishIndex(IndexFile(engineID: engineID, voiceID: voiceID, createdAt: Date(), paragraphs: entries),
                         for: articleID)
        bumpContentRevision()
    }

    /// Once the index is saved: CAFs the previous index listed that it doesn't, and `m-` / `s-`
    /// files an interrupted change wrote but never listed. A file either index (saved or in
    /// memory) lists stays.
    func removeUnlisted(articleID: UUID, previous: IndexFile?) throws {
        let dir = directory(for: articleID)
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        let listed = Set((index(for: articleID)?.paragraphs ?? []).map(\.file))
            .union((readIndexFile(for: articleID)?.paragraphs ?? []).map(\.file))
        let leftovers = names.filter { ($0.hasPrefix("m-") || $0.hasPrefix("s-")) && $0.hasSuffix(".caf") }
        let doomed = Set((previous?.paragraphs ?? []).map(\.file)).union(leftovers).subtracting(listed)
        for name in doomed.sorted() where fileManager.fileExists(atPath: dir.appendingPathComponent(name).path) {
            try fileManager.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
