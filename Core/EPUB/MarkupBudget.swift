import Foundation

/// The markup caps of `EPUBLimits` for one book, charged while each file is read and parsed:
/// a text file's size, the text across the book, nesting depth, and markup nodes per file and
/// across the book. One budget is shared by every file a book's import reads, so the totals are
/// the book's; both parsers (`XMLTree` and `XHTMLReader`) charge it as they go and stop with
/// `EPUBError.tooLarge` before building more.
final class MarkupBudget {
    let limits: EPUBLimits
    private var textBytes = 0
    private var nodes = 0

    init(limits: EPUBLimits = .standard) {
        self.limits = limits
    }

    /// A text file's bytes, read within the per-file cap and what's left of the book's.
    /// Throws `.unreadable` when it's missing or damaged.
    func readText(_ path: String, from archive: EPUBArchive) throws -> Data {
        let left = max(0, limits.maxTextBytes - textBytes)
        let data = try archive.data(at: path, maxBytes: Int64(min(limits.maxTextFileBytes, left)))
        textBytes += data.count
        return data
    }

    /// The same, or nil when the archive has no such entry. Damage still throws.
    func readTextIfPresent(_ path: String, from archive: EPUBArchive) throws -> Data? {
        guard archive.contains(path) else { return nil }
        return try readText(path, from: archive)
    }

    /// A counter for parsing one file against this budget.
    func counter() -> MarkupCounter {
        MarkupCounter(budget: self)
    }

    fileprivate func chargeNode() throws {
        nodes += 1
        guard nodes <= limits.maxNodes else { throw EPUBError.tooLarge }
    }
}

/// Counts one file's markup as a parser reads it: nodes against the file's cap and the book's,
/// nesting against the depth cap.
struct MarkupCounter {
    fileprivate let budget: MarkupBudget
    private var nodes = 0

    fileprivate init(budget: MarkupBudget) {
        self.budget = budget
    }

    mutating func countNodes(_ count: Int = 1) throws {
        for _ in 0..<count {
            nodes += 1
            guard nodes <= budget.limits.maxNodesPerFile else { throw EPUBError.tooLarge }
            try budget.chargeNode()
        }
    }

    /// Throws when `depth` elements open at once is past the cap.
    func checkDepth(_ depth: Int) throws {
        guard depth <= budget.limits.maxNestingDepth else { throw EPUBError.tooLarge }
    }
}
