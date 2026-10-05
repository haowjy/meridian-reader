import CryptoKit
import Foundation

/// Stable keys for imported books and their chapters. The chapter key is the chapter's audio
/// cache key, so importing the same file again gives the same keys and its audio is reused.
///
/// Each key is SHA-256(namespace, fields) → UUID, the fields written one after another as their
/// UTF-8 byte count (8 bytes, big-endian) then their bytes, so no field's content can be read as
/// a boundary between two.
/// - **Book key** fields: `"identifier"`, the OPF unique identifier, the title (whitespace
///   collapsed). The title is part of it because editions share identifiers (Gutenberg's EPUB2
///   and EPUB3 files). An identifier that is missing or a placeholder (`urn:uuid:` of all zeros)
///   gives `"file"` and the file's SHA-256 instead.
/// - **Chapter key** fields: the book key, the spine file's package path, then the anchor:
///   `"start"`; `"id"` and the id; or `"text"`, the first block's fingerprint and its occurrence.
///   It doesn't go through `ArticleIdentity.canonicalURLString`, which drops fragments: two
///   chapters cut from one file differ only in their anchor.
///
/// These namespaces and fields are persisted identity: changing them needs a migration.
enum BookIdentity {
    private static let bookNamespace = "com.jimmyyao.Reader.book.v1"
    private static let chapterNamespace = "com.jimmyyao.Reader.book-chapter.v1"

    static func bookKey(identifier: String?, title: String?, fileFingerprint: String) -> UUID {
        if let identifier = usableIdentifier(identifier) {
            return key(bookNamespace, ["identifier", identifier, title?.collapsingWhitespace ?? ""])
        }
        return key(bookNamespace, ["file", fileFingerprint])
    }

    static func chapterKey(bookKey: UUID, locator: EPUBLocator) -> UUID {
        var fields = [bookKey.uuidString, locator.href]
        switch locator.anchor {
        case .fileStart: fields += ["start"]
        case .id(let id): fields += ["id", id]
        case .text(let fingerprint, let occurrence): fields += ["text", fingerprint, String(occurrence)]
        }
        return key(chapterNamespace, fields)
    }

    private static func key(_ namespace: String, _ fields: [String]) -> UUID {
        var encoded = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            encoded.append(contentsOf: withUnsafeBytes(of: UInt64(bytes.count).bigEndian, Array.init))
            encoded.append(bytes)
        }
        return ArticleIdentity.uuid(from: [Data(namespace.utf8), encoded])
    }

    /// The identifier, trimmed, or nil when it's empty or a placeholder of zeros.
    static func usableIdentifier(_ identifier: String?) -> String? {
        guard let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        var bare = Substring(trimmed)
        for prefix in ["urn:uuid:", "uuid:"] where bare.lowercased().hasPrefix(prefix) {
            bare = bare.dropFirst(prefix.count)
            break
        }
        let isPlaceholder = bare.allSatisfy { $0 == "0" || $0 == "-" }
        return isPlaceholder ? nil : trimmed
    }

    /// SHA-256 of the file's bytes, hex.
    static func fileFingerprint(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
