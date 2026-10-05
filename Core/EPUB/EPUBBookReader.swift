import Foundation

/// A book read from an EPUB and cut into chapters: what an import hands the library.
struct EPUBBook: Sendable {
    var key: UUID
    /// SHA-256 of the file, hex.
    var fileFingerprint: String
    var metadata: EPUBMetadata
    var cover: EPUBCover?
    /// The whole table of contents, as the book gives it.
    var contents: [EPUBContentsEntry]
    var chapters: [EPUBChapter]
    /// Spine files read; the import's progress counts these.
    var spineCount: Int
}

struct EPUBCover: Equatable, Sendable {
    var path: String
    var mediaType: String
    var data: Data
}

/// One chapter: a span of the book's markup, cut at a contents anchor (or a fallback cut).
struct EPUBChapter: Equatable, Sendable {
    /// Position in reading order, from 0.
    var ordinal: Int
    /// `BookIdentity.chapterKey`: stable across re-imports of the same file.
    var key: UUID
    var title: String?
    var locator: EPUBLocator
    /// Spine files the chapter runs across, in order.
    var spineHrefs: [String]
    var wordCount: Int
    /// Wholly front or back matter (or a short unlisted page such as the cover).
    var skipsInPlayback: Bool
    /// The chapter's markup as body-level XHTML, not yet normalized into listen blocks.
    var xhtml: String
}

/// Reads an EPUB into an `EPUBBook`: refusals first (rights files, then encrypted text or fixed
/// layout), then the package, the contents, every spine file, and the cut.
enum EPUBBookReader {
    static func read(fileURL: URL, limits: EPUBLimits = .standard, rules: EPUBCutRules = .standard) throws -> EPUBBook {
        let container = try EPUBContainer(fileURL: fileURL, limits: limits)
        return try read(container, fileFingerprint: try BookIdentity.fileFingerprint(of: fileURL), rules: rules)
    }

    static func read(_ archive: EPUBArchive, fileFingerprint: String, rules: EPUBCutRules = .standard) throws -> EPUBBook {
        try EPUBRefusals.checkRightsFiles(in: archive)
        let package = try EPUBPackage.read(from: archive)
        try EPUBRefusals.check(package, in: archive)
        let contents = try EPUBContents.read(package, from: archive)

        var documents: [EPUBSpineDocument] = []
        for item in package.spine {
            guard let data = try archive.dataIfPresent(at: item.path) else { continue }
            // The nav listed in the spine is the contents page: never read as part of a chapter.
            let isNav = item.path.lowercased() == package.navPath?.lowercased()
            documents.append(EPUBSpineDocument(path: item.path, data: data, linear: item.linear && !isNav))
        }
        guard !documents.isEmpty else { throw EPUBError.unreadable("no text documents") }
        let unmarked = EPUBTextStream(documents: documents)
        let boundaries = matterBoundaries(package: package, contents: contents, stream: unmarked)
        let stream = EPUBTextStream(documents: documents, bodyStart: boundaries.body, backStart: boundaries.back)
        guard stream.totalWords > 0 else { throw EPUBError.unreadable("no text") }

        var metadata = package.metadata
        if metadata.language == nil {
            metadata.language = documents.lazy.compactMap(\.language).first
        }
        let bookKey = BookIdentity.bookKey(identifier: metadata.identifier, title: metadata.title,
                                           fileFingerprint: fileFingerprint)
        let cuts = EPUBChapterCutter(stream: stream, rules: rules).cut(contents: contents.entries)
        let chapters = cuts.enumerated().map { ordinal, cut in
            EPUBChapter(
                ordinal: ordinal,
                key: BookIdentity.chapterKey(bookKey: bookKey, locator: cut.locator),
                title: cut.title,
                locator: cut.locator,
                spineHrefs: stream.paths(from: cut.start, to: cut.end),
                wordCount: cut.wordCount,
                skipsInPlayback: cut.skipsInPlayback,
                xhtml: stream.xhtml(from: cut.start, to: cut.end)
            )
        }
        return EPUBBook(key: bookKey, fileFingerprint: fileFingerprint, metadata: metadata,
                        cover: try cover(of: package, in: archive), contents: contents.entries,
                        chapters: chapters, spineCount: documents.count)
    }

    /// Where the body starts: EPUB3 landmarks' `bodymatter`, else the EPUB2 guide's `text`. Where
    /// back matter starts: the landmarks' `backmatter`, when it comes after the body's start.
    private static func matterBoundaries(package: EPUBPackage, contents: EPUBContents,
                                         stream: EPUBTextStream) -> (body: EPUBTextStream.Position?,
                                                                     back: EPUBTextStream.Position?) {
        var body: EPUBTextStream.Position?
        if let landmark = contents.landmarks.first(where: { $0.types.contains("bodymatter") }) {
            body = stream.position(ofPath: landmark.path, fragment: landmark.fragment)
        } else if let text = package.guide.first(where: { $0.type == "text" }) {
            body = stream.position(ofPath: text.path, fragment: text.fragment)
        }
        var back = contents.landmarks.first { $0.types.contains("backmatter") }.flatMap {
            stream.position(ofPath: $0.path, fragment: $0.fragment)
        }
        if let start = back, start <= (body ?? stream.start) { back = nil }
        return (body, back)
    }

    /// The `cover-image` item, else `<meta name="cover">`, else the guide's cover: the image
    /// itself, or the first image on the cover page it names.
    private static func cover(of package: EPUBPackage, in archive: EPUBArchive) throws -> EPUBCover? {
        var path = package.coverImagePath
        if path == nil, let page = package.guide.first(where: { $0.type == "cover" }) {
            let item = package.manifest.first { $0.path.lowercased() == page.path.lowercased() }
            if item?.mediaType.hasPrefix("image/") == true {
                path = page.path
            } else if let data = try archive.dataIfPresent(at: page.path) {
                let tree = XHTMLReader.tree(from: data)
                let source = tree.firstDescendant(named: "img")?.attribute("src")
                    ?? tree.firstDescendant(named: "image").flatMap { $0.attribute("xlink:href") ?? $0.attribute("href") }
                path = source.flatMap { EPUBPath.resolve($0, relativeTo: page.path)?.path }
            }
        }
        guard let path, let stored = archive.entryPath(matching: path),
              let data = try archive.dataIfPresent(at: stored) else { return nil }
        let mediaType = package.manifest.first { $0.path.lowercased() == stored.lowercased() }?.mediaType
        return EPUBCover(path: stored, mediaType: mediaType ?? "", data: data)
    }
}
