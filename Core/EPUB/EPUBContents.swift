import Foundation

/// One entry of the book's table of contents.
struct EPUBContentsEntry: Equatable, Sendable {
    var title: String
    /// Package path of the target; nil for a heading that links nowhere (a nav `<span>`).
    var path: String?
    var fragment: String?
    var children: [EPUBContentsEntry] = []
}

/// An EPUB3 `landmarks` entry (`bodymatter`, `backmatter`, `toc`, …).
struct EPUBLandmark: Equatable, Sendable {
    var types: Set<String>
    var path: String
    var fragment: String?
}

/// The whole table of contents tree (EPUB3 nav, else the EPUB2 NCX) and the landmarks.
struct EPUBContents: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case nav, ncx, none
    }

    var entries: [EPUBContentsEntry]
    var source: Source
    var landmarks: [EPUBLandmark]

    /// A contents document that's missing is passed over (cutting falls back to headings); one
    /// that's damaged, or an NCX that isn't well-formed XML, fails the import.
    static func read(_ package: EPUBPackage, from archive: EPUBArchive, budget: MarkupBudget) throws -> EPUBContents {
        var landmarks: [EPUBLandmark] = []
        if let navPath = package.navPath, let data = try budget.readTextIfPresent(navPath, from: archive) {
            let navs = try XHTMLReader.tree(from: data, budget: budget).descendants(named: "nav")
            landmarks = navs.first { $0.tokens(of: "epub:type").contains("landmarks") }
                .map { landmarkEntries(in: $0, navPath: navPath, archive: archive) } ?? []
            let toc = navs.first { $0.tokens(of: "epub:type").contains("toc") }
                ?? navs.first { $0.attribute("epub:type") == nil }
            let list = toc.flatMap { $0.firstDescendant(named: "ol") ?? $0.firstDescendant(named: "ul") }
            let navEntries = list.map { entries(of: $0, navPath: navPath, archive: archive) } ?? []
            if navEntries.contains(where: \.hasTarget) {
                return EPUBContents(entries: navEntries, source: .nav, landmarks: landmarks)
            }
        }
        if let ncxPath = package.ncxPath, let data = try budget.readTextIfPresent(ncxPath, from: archive),
           let navMap = try XMLTree.parse(data, named: ncxPath, budget: budget).firstDescendant(named: "navmap") {
            let ncxEntries = navMap.elements(named: "navpoint").compactMap {
                navPoint($0, ncxPath: ncxPath, archive: archive)
            }
            if ncxEntries.contains(where: \.hasTarget) {
                return EPUBContents(entries: ncxEntries, source: .ncx, landmarks: landmarks)
            }
        }
        return EPUBContents(entries: [], source: .none, landmarks: landmarks)
    }

    // MARK: - EPUB3 nav

    private static func entries(of list: MarkupElement, navPath: String, archive: EPUBArchive) -> [EPUBContentsEntry] {
        list.elements(named: "li").compactMap { entry(from: $0, navPath: navPath, archive: archive) }
    }

    private static func entry(from item: MarkupElement, navPath: String, archive: EPUBArchive) -> EPUBContentsEntry? {
        let label = item.elements.first { $0.localName == "a" || $0.localName == "span" }
        var title = label?.text ?? ""
        if title.isEmpty { title = label?.attribute("title")?.collapsingWhitespace ?? "" }
        var target: (path: String, fragment: String?)?
        if let label, label.localName == "a", let href = label.attribute("href") {
            target = resolve(href, relativeTo: navPath, archive: archive)
        }
        let nested = item.elements.first { $0.localName == "ol" || $0.localName == "ul" }
        let children = nested.map { entries(of: $0, navPath: navPath, archive: archive) } ?? []
        guard target != nil || !children.isEmpty else { return nil }
        return EPUBContentsEntry(title: title, path: target?.path, fragment: target?.fragment, children: children)
    }

    private static func landmarkEntries(in nav: MarkupElement, navPath: String,
                                        archive: EPUBArchive) -> [EPUBLandmark] {
        nav.descendants(named: "a").compactMap { link in
            guard let href = link.attribute("href"),
                  let target = resolve(href, relativeTo: navPath, archive: archive) else { return nil }
            return EPUBLandmark(types: link.tokens(of: "epub:type"), path: target.path, fragment: target.fragment)
        }
    }

    // MARK: - EPUB2 NCX

    private static func navPoint(_ element: MarkupElement, ncxPath: String, archive: EPUBArchive) -> EPUBContentsEntry? {
        let label = element.firstElement(named: "navlabel")
        let title = label?.firstElement(named: "text")?.text ?? label?.text ?? ""
        let target = element.firstElement(named: "content")?.attribute("src").flatMap {
            resolve($0, relativeTo: ncxPath, archive: archive)
        }
        let children = element.elements(named: "navpoint").compactMap {
            navPoint($0, ncxPath: ncxPath, archive: archive)
        }
        guard target != nil || !children.isEmpty else { return nil }
        return EPUBContentsEntry(title: title, path: target?.path, fragment: target?.fragment, children: children)
    }

    private static func resolve(_ href: String, relativeTo base: String,
                                archive: EPUBArchive) -> (path: String, fragment: String?)? {
        guard let resolved = EPUBPath.resolve(href, relativeTo: base) else { return nil }
        return (archive.entryPath(matching: resolved.path) ?? resolved.path, resolved.fragment)
    }
}

private extension EPUBContentsEntry {
    var hasTarget: Bool {
        path != nil || children.contains(where: \.hasTarget)
    }
}
