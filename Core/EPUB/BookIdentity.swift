import CryptoKit
import Foundation

/// Stable keys for imported books and their chapters. The chapter key is the chapter's audio
/// cache key, so importing the same file again gives the same keys and its audio is reused.
///
/// - **Book key** = SHA-256(book namespace, OPF unique identifier + "\n" + title). The title is
///   part of it because editions share identifiers (Gutenberg's EPUB2 and EPUB3 files). An
///   identifier that is missing or a placeholder (`urn:uuid:` of all zeros) is replaced by the
///   file's SHA-256.
/// - **Chapter key** = SHA-256(chapter namespace, book key, href + "#" + fragment). It doesn't
///   go through `ArticleIdentity.canonicalURLString`, which drops fragments: two chapters cut
///   from one file differ only in their fragment.
///
/// These namespaces and inputs are persisted identity: changing them needs a migration.
enum BookIdentity {
    private static let bookNamespace = "com.jimmyyao.Reader.book.v1"
    private static let chapterNamespace = "com.jimmyyao.Reader.book-chapter.v1"

    static func bookKey(identifier: String?, title: String?, fileFingerprint: String) -> UUID {
        let namespace = Data(bookNamespace.utf8)
        if let identifier = usableIdentifier(identifier) {
            let title = title?.collapsingWhitespace ?? ""
            return ArticleIdentity.uuid(from: [namespace, Data((identifier + "\n" + title).utf8)])
        }
        return ArticleIdentity.uuid(from: [namespace, Data(("file\n" + fileFingerprint).utf8)])
    }

    static func chapterKey(bookKey: UUID, locator: EPUBLocator) -> UUID {
        ArticleIdentity.uuid(from: [
            Data(chapterNamespace.utf8),
            Data(bookKey.uuidString.utf8),
            Data((locator.href + "#" + (locator.fragment ?? "")).utf8),
        ])
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
