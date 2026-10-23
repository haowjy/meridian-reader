import Foundation
import PDFKit
import UIKit

/// Why a PDF wasn't read, as the import sheet's one-line reason.
enum PDFError: Error, Equatable {
    /// Password-protected (or still locked after an empty unlock).
    case encrypted
    /// No extractable text on any page (image-only / scanned with no OCR).
    case noText
    /// Not a PDF, damaged, or otherwise unreadable. Detail is for the log.
    case unreadable(String)
}

/// A PDF read into chapters: what a PDF import hands the library.
struct PDFBook: Sendable {
    var key: UUID
    /// SHA-256 of the file, hex.
    var fileFingerprint: String
    var title: String
    var author: String?
    /// First-page thumbnail JPEG, when rendering worked.
    var coverJPEG: Data?
    /// One chapter per text page (empty pages skipped); a page over the cut bar is split.
    var chapters: [PDFChapter]
}

/// One PDF chapter: a page's (or page-slice's) plain text, not yet wrapped as listen HTML.
struct PDFChapter: Equatable, Sendable {
    var ordinal: Int
    /// `BookIdentity.chapterKey`: stable across re-imports of the same file.
    var key: UUID
    /// "Page N", or "Page N · 2" when a long page was split.
    var title: String?
    var locator: EPUBLocator
    var plainText: String
    var provisionalWordCount: Int
}

/// Reads a PDF with PDFKit into a `PDFBook`: refuses encrypted / locked files and files with no
/// extractable text (no OCR). **Choice:** one library chapter per text page so listening can
/// progress page by page; blank pages are skipped; a page over `maxWords` is split into further
/// chapters (`Page N · 2`, …). Layout, columns, and footnotes are not reconstructed — only
/// `PDFPage.string`.
enum PDFBookReader {
    /// Soft cap matching `EPUBCutRules.standard.maxWords` so `BookChapterFinalizer` rarely re-cuts.
    static let maxWordsPerChapter = EPUBCutRules.standard.maxWords

    static func read(fileURL: URL, maxWords: Int = maxWordsPerChapter) throws -> PDFBook {
        guard let document = PDFDocument(url: fileURL) else {
            throw PDFError.unreadable("not a PDF")
        }
        if document.isEncrypted {
            // Empty password unlocks many "open" restrictions; a real password fails.
            guard document.unlock(withPassword: "") else { throw PDFError.encrypted }
        }
        guard !document.isLocked else { throw PDFError.encrypted }
        guard document.pageCount > 0 else { throw PDFError.unreadable("no pages") }

        let fingerprint = try BookIdentity.fileFingerprint(of: fileURL)
        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        let attrs = document.documentAttributes
        let metaTitle = (attrs?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String = {
            if let metaTitle, !metaTitle.isEmpty { return metaTitle }
            return fallbackTitle
        }()
        let metaAuthor = (attrs?[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author: String? = {
            guard let metaAuthor, !metaAuthor.isEmpty else { return nil }
            return metaAuthor
        }()

        let bookKey = BookIdentity.bookKey(identifier: nil, title: title, fileFingerprint: fingerprint)
        var chapters: [PDFChapter] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let raw = page.string ?? ""
            let text = Self.normalizePageText(raw)
            guard !text.isEmpty, WordCount.count(text) > 0 else { continue }
            let pageNumber = pageIndex + 1
            let pieces = Self.split(text, maxWords: maxWords)
            for (pieceIndex, piece) in pieces.enumerated() {
                let href = pieces.count == 1
                    ? "page/\(pageNumber)"
                    : "page/\(pageNumber)/\(pieceIndex + 1)"
                let locator = EPUBLocator(href: href, anchor: .fileStart)
                let label: String = pieces.count == 1
                    ? "Page \(pageNumber)"
                    : "Page \(pageNumber) · \(pieceIndex + 1)"
                chapters.append(PDFChapter(
                    ordinal: chapters.count,
                    key: BookIdentity.chapterKey(bookKey: bookKey, locator: locator),
                    title: label,
                    locator: locator,
                    plainText: piece,
                    provisionalWordCount: WordCount.count(piece)))
            }
        }
        guard !chapters.isEmpty else { throw PDFError.noText }

        return PDFBook(
            key: bookKey,
            fileFingerprint: fingerprint,
            title: title,
            author: author,
            coverJPEG: Self.coverJPEG(of: document),
            chapters: chapters)
    }

    /// Collapse odd PDF whitespace: CRLF → LF, runs of blank lines → one, trim ends.
    private static func normalizePageText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pack paragraphs under `maxWords`; a single overlong paragraph is sliced by words.
    private static func split(_ text: String, maxWords: Int) -> [String] {
        let maxWords = max(1, maxWords)
        if WordCount.count(text) <= maxWords { return [text] }
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        var current = ""
        var currentWords = 0
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(trimmed) }
            current = ""
            currentWords = 0
        }
        for paragraph in paragraphs {
            let words = WordCount.count(paragraph)
            if words > maxWords {
                flush()
                out.append(contentsOf: wordSlices(paragraph, maxWords: maxWords))
                continue
            }
            if currentWords > 0, currentWords + words > maxWords { flush() }
            if current.isEmpty {
                current = paragraph
            } else {
                current += "\n\n" + paragraph
            }
            currentWords += words
        }
        flush()
        return out.isEmpty ? [text] : out
    }

    private static func wordSlices(_ text: String, maxWords: Int) -> [String] {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            let end = min(i + maxWords, tokens.count)
            out.append(tokens[i..<end].joined(separator: " "))
            i = end
        }
        return out
    }

    private static func coverJPEG(of document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        return CoverThumbnail.make(from: data)
    }
}
