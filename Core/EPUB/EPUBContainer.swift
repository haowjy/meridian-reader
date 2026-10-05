import Foundation
import ZIPFoundation

/// Why a file can't be read as a book.
enum EPUBError: Error, Equatable {
    /// An encrypted spine or contents document, or a rights file (Adobe, Readium LCP, Apple).
    case drmProtected
    /// A pre-paginated (fixed-layout) book: its pages are pictures of text with no reading order.
    case fixedLayout
    /// Over the uncompressed-size or entry-count cap: a zip bomb, or far more than a book needs.
    case tooLarge
    /// An entry whose path is absolute or climbs out of the archive.
    case unsafePath(String)
    /// Not a zip, no package document, or no text in it.
    case unreadable(String)
}

/// Caps applied while opening and reading an EPUB. Text is small (all of a long novel's XHTML
/// is a few MB); the caps are far above any real book and far below what would exhaust memory.
struct EPUBLimits: Equatable, Sendable {
    /// Total bytes after decompression: declared by the archive, and counted again while reading.
    var maxUncompressedBytes: Int64 = 200 * 1024 * 1024
    var maxEntryCount = 5_000

    static let standard = EPUBLimits()
}

/// Read access to the files inside an EPUB by package path (`OEBPS/text/ch1.xhtml`), so the
/// parser doesn't depend on the zip library.
protocol EPUBArchive {
    /// The stored path for `path`: an exact match, else the only entry matching it ignoring case.
    func entryPath(matching path: String) -> String?
    /// The entry's bytes. Throws `EPUBError.tooLarge` once reading would pass the cap.
    func data(at path: String) throws -> Data
}

extension EPUBArchive {
    func contains(_ path: String) -> Bool {
        entryPath(matching: path) != nil
    }
}

/// An EPUB file opened with ZIPFoundation. Opening checks the central directory against the
/// caps and refuses unsafe entry paths; every read is counted against the size cap again, so an
/// entry that inflates past what its header declares is stopped as it inflates.
final class EPUBContainer: EPUBArchive {
    private let archive: Archive
    private let limits: EPUBLimits
    private var entries: [String: Entry] = [:]
    /// Lowercased path → stored path, for paths that differ only in case from one stored path.
    private var caseInsensitive: [String: String?] = [:]
    private var bytesRead: Int64 = 0

    init(fileURL: URL, limits: EPUBLimits = .standard) throws {
        do {
            archive = try Archive(url: fileURL, accessMode: .read)
        } catch {
            throw EPUBError.unreadable("not a zip archive")
        }
        self.limits = limits
        var count = 0
        var declaredBytes: Int64 = 0
        for entry in archive {
            count += 1
            guard count <= limits.maxEntryCount else { throw EPUBError.tooLarge }
            let path = entry.path
            guard EPUBPath.isSafeEntryPath(path) else { throw EPUBError.unsafePath(path) }
            guard entry.type == .file else { continue }
            // Compared unsigned before adding: a ZIP64 size can be anything up to 2^64 − 1.
            guard entry.uncompressedSize <= UInt64(limits.maxUncompressedBytes - declaredBytes) else {
                throw EPUBError.tooLarge
            }
            declaredBytes += Int64(entry.uncompressedSize)
            let stored = EPUBPath.normalizedEntryPath(path)
            guard entries[stored] == nil else { continue }
            entries[stored] = entry
            let folded = stored.lowercased()
            caseInsensitive[folded] = caseInsensitive[folded] == nil ? stored : .some(nil)
        }
    }

    func entryPath(matching path: String) -> String? {
        if entries[path] != nil { return path }
        return caseInsensitive[path.lowercased()] ?? nil
    }

    func data(at path: String) throws -> Data {
        guard let stored = entryPath(matching: path), let entry = entries[stored] else {
            throw EPUBError.unreadable("missing \(path)")
        }
        let budget = limits.maxUncompressedBytes - bytesRead
        let declared = Int64(clamping: entry.uncompressedSize)
        guard declared <= budget else { throw EPUBError.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(min(declared, 4 * 1024 * 1024)))
        do {
            let checksum = try archive.extract(entry, skipCRC32: false) { chunk in
                // An entry may not inflate past its declared size, nor the archive past its cap.
                let total = Int64(data.count + chunk.count)
                guard total <= declared, total <= budget else { throw EPUBError.tooLarge }
                data.append(chunk)
            }
            guard checksum == entry.checksum else { throw EPUBError.unreadable("\(stored) is damaged") }
        } catch let error as EPUBError {
            throw error
        } catch {
            throw EPUBError.unreadable("\(stored) can't be unzipped")
        }
        bytesRead += Int64(data.count)
        return data
    }
}

/// Paths inside the package: entry names, and hrefs resolved against the file they appear in.
enum EPUBPath {
    /// False for a name that is absolute (`/x`, `C:\x`) or has a `..` component.
    static func isSafeEntryPath(_ path: String) -> Bool {
        let unified = path.replacingOccurrences(of: "\\", with: "/")
        if unified.hasPrefix("/") || unified.contains("\0") { return false }
        let components = unified.split(separator: "/", omittingEmptySubsequences: true)
        if let first = components.first, first.count == 2, first.hasSuffix(":") { return false }
        return !components.contains("..")
    }

    /// The name as the package refers to it: no leading `./`.
    static func normalizedEntryPath(_ path: String) -> String {
        var path = path
        while path.hasPrefix("./") { path.removeFirst(2) }
        return path
    }

    /// The folder holding a package path: `OEBPS/text/ch1.xhtml` → `OEBPS/text`; top level → "".
    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// Resolves an href (a relative URL) against the package path of the file it appears in.
    /// Returns the target's package path and its fragment, both percent-decoded. Nil for an
    /// absolute URL (`http:`, `mailto:`), or a path that climbs out of the archive.
    static func resolve(_ href: String, relativeTo basePath: String) -> (path: String, fragment: String?)? {
        var reference = href.trimmingCharacters(in: .whitespacesAndNewlines)
        var fragment: String?
        if let hash = reference.firstIndex(of: "#") {
            let raw = String(reference[reference.index(after: hash)...])
            fragment = raw.isEmpty ? nil : (raw.removingPercentEncoding ?? raw)
            reference = String(reference[..<hash])
        }
        if let query = reference.firstIndex(of: "?") {
            reference = String(reference[..<query])
        }
        if hasScheme(reference) { return nil }
        if reference.isEmpty { return (basePath, fragment) }
        let decoded = reference.removingPercentEncoding ?? reference
        let joined = decoded.hasPrefix("/") ? decoded : directory(of: basePath) + "/" + decoded
        var components: [Substring] = []
        for component in joined.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default: components.append(component)
            }
        }
        guard !components.isEmpty else { return nil }
        return (components.joined(separator: "/"), fragment)
    }

    private static func hasScheme(_ reference: String) -> Bool {
        guard let colon = reference.firstIndex(of: ":") else { return false }
        let scheme = reference[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
    }
}
