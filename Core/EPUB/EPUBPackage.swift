import Foundation

/// The book's details from its package document.
struct EPUBMetadata: Equatable, Sendable {
    var title: String?
    /// Creators credited as authors (MARC role `aut`, or no role); every creator when none is.
    var authors: [String]
    var language: String?
    /// The `dc:identifier` named by the package's `unique-identifier`, else the first one.
    var identifier: String?
}

struct EPUBManifestItem: Equatable, Sendable {
    var id: String
    var path: String
    var mediaType: String
    var properties: Set<String>
}

struct EPUBSpineItem: Equatable, Sendable {
    var path: String
    var mediaType: String
    /// `linear="no"`: an auxiliary page (a cover, a pop-up note) outside the reading order.
    var linear: Bool
    var properties: Set<String>
}

/// An EPUB2 `<guide>` reference.
struct EPUBGuideReference: Equatable, Sendable {
    var type: String
    var path: String
    var fragment: String?
}

/// `META-INF/container.xml` → the OPF: metadata, manifest, spine, guide, and where the
/// contents and cover are.
struct EPUBPackage: Equatable, Sendable {
    var packagePath: String
    var version: String?
    var metadata: EPUBMetadata
    var manifest: [EPUBManifestItem]
    /// Text documents in reading order; spine entries that aren't XHTML are left out.
    var spine: [EPUBSpineItem]
    /// The EPUB3 navigation document.
    var navPath: String?
    /// The EPUB2 NCX: the one `spine@toc` names, else any manifest item of the NCX type.
    var ncxPath: String?
    var guide: [EPUBGuideReference]
    /// `cover-image` property, else `<meta name="cover">`; a guide cover page is resolved later.
    var coverImagePath: String?
    /// `rendition:layout` is `pre-paginated` for the whole book.
    var isPrePaginated: Bool

    static let containerPath = "META-INF/container.xml"
    static let xhtmlMediaTypes: Set<String> = ["application/xhtml+xml", "text/html"]

    static func read(from archive: EPUBArchive, budget: MarkupBudget) throws -> EPUBPackage {
        guard archive.contains(containerPath) else { throw EPUBError.unreadable("no META-INF/container.xml") }
        let container = try XMLTree.parse(try budget.readText(containerPath, from: archive), named: containerPath,
                                          budget: budget)
        let rootfiles = container.descendants(named: "rootfile")
        let chosen = rootfiles.first { $0.attribute("media-type") == "application/oebps-package+xml" }
            ?? rootfiles.first
        guard let fullPath = chosen?.attribute("full-path"),
              let resolved = EPUBPath.resolve(fullPath, relativeTo: ""),
              let packagePath = archive.entryPath(matching: resolved.path) else {
            throw EPUBError.unreadable("no package document")
        }
        let opf = try XMLTree.parse(try budget.readText(packagePath, from: archive), named: packagePath, budget: budget)
        guard opf.localName == "package" else { throw EPUBError.unreadable("no package document") }
        return try EPUBPackage(opf: opf, packagePath: packagePath, archive: archive)
    }

    private init(opf: MarkupElement, packagePath: String, archive: EPUBArchive) throws {
        self.packagePath = packagePath
        version = opf.attribute("version")
        let metadataElement = opf.firstElement(named: "metadata") ?? MarkupElement(name: "metadata", attributes: [:])
        metadata = EPUBPackage.metadata(from: metadataElement, uniqueIdentifier: opf.attribute("unique-identifier"))

        var manifest: [EPUBManifestItem] = []
        for item in opf.firstElement(named: "manifest")?.elements(named: "item") ?? [] {
            guard let id = item.attribute("id"), let href = item.attribute("href"),
                  let resolved = EPUBPath.resolve(href, relativeTo: packagePath) else { continue }
            manifest.append(EPUBManifestItem(
                id: id,
                path: archive.entryPath(matching: resolved.path) ?? resolved.path,
                mediaType: (item.attribute("media-type") ?? "").lowercased(),
                properties: item.tokens(of: "properties")
            ))
        }
        self.manifest = manifest
        let byID = Dictionary(manifest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let spineElement = opf.firstElement(named: "spine")
        spine = (spineElement?.elements(named: "itemref") ?? []).compactMap { itemref in
            guard let idref = itemref.attribute("idref"), let item = byID[idref],
                  EPUBPackage.xhtmlMediaTypes.contains(item.mediaType) else { return nil }
            return EPUBSpineItem(
                path: item.path,
                mediaType: item.mediaType,
                linear: itemref.attribute("linear")?.lowercased() != "no",
                properties: itemref.tokens(of: "properties")
            )
        }
        navPath = manifest.first { $0.properties.contains("nav") }?.path
        let ncxType = "application/x-dtbncx+xml"
        if let tocID = spineElement?.attribute("toc"), let item = byID[tocID] {
            ncxPath = item.path
        } else {
            ncxPath = manifest.first { $0.mediaType == ncxType }?.path
        }

        guide = (opf.firstElement(named: "guide")?.elements(named: "reference") ?? []).compactMap { reference in
            guard let type = reference.attribute("type"), let href = reference.attribute("href"),
                  let resolved = EPUBPath.resolve(href, relativeTo: packagePath) else { return nil }
            return EPUBGuideReference(type: type.lowercased(),
                                      path: archive.entryPath(matching: resolved.path) ?? resolved.path,
                                      fragment: resolved.fragment)
        }

        let metas = metadataElement.elements(named: "meta")
        if let coverItem = manifest.first(where: { $0.properties.contains("cover-image") }) {
            coverImagePath = coverItem.path
        } else if let coverRef = metas.first(where: { $0.attribute("name")?.lowercased() == "cover" })?
                    .attribute("content"), !coverRef.isEmpty,
                  let item = byID[coverRef] ?? manifest.first(where: { $0.path.hasSuffix(coverRef) }),
                  item.mediaType.hasPrefix("image/") {
            coverImagePath = item.path
        } else {
            coverImagePath = nil
        }

        let layout = metas.first { $0.attribute("property") == "rendition:layout" }?.text.lowercased()
        let spineLayouts = spine.map(\.properties)
        let everyItemPrePaginated = !spineLayouts.isEmpty
            && spineLayouts.allSatisfy { $0.contains("rendition:layout-pre-paginated") }
        let everyItemReflowable = !spineLayouts.isEmpty
            && spineLayouts.allSatisfy { $0.contains("rendition:layout-reflowable") }
        isPrePaginated = everyItemPrePaginated || (layout == "pre-paginated" && !everyItemReflowable)
    }

    // MARK: - Metadata

    private static func metadata(from element: MarkupElement, uniqueIdentifier: String?) -> EPUBMetadata {
        // EPUB3 refinements: `<meta refines="#id" property="…">value</meta>`.
        var refinements: [String: [String: String]] = [:]
        for meta in element.elements(named: "meta") {
            guard let refines = meta.attribute("refines"), let property = meta.attribute("property") else { continue }
            let id = refines.hasPrefix("#") ? String(refines.dropFirst()) : refines
            refinements[id, default: [:]][property.lowercased()] = meta.text.lowercased()
        }
        func refinement(_ element: MarkupElement, _ property: String) -> String? {
            element.attribute("id").flatMap { refinements[$0]?[property] }
        }

        let titles = element.elements(named: "title").filter { !$0.text.isEmpty }
        let title = (titles.first { refinement($0, "title-type") == "main" } ?? titles.first)?.text

        let creators = element.elements(named: "creator").filter { !$0.text.isEmpty }
        let roles = creators.map { creator in
            (creator.attribute("opf:role") ?? creator.attribute("role") ?? refinement(creator, "role"))?.lowercased()
        }
        let authorIndices = creators.indices.filter { roles[$0] == nil || roles[$0] == "aut" }
        var authors: [String] = []
        for index in (authorIndices.isEmpty ? Array(creators.indices) : authorIndices) {
            let name = creators[index].text
            if !authors.contains(name) { authors.append(name) }
        }

        let identifiers = element.elements(named: "identifier")
        let identifier = (identifiers.first { $0.attribute("id") == uniqueIdentifier && uniqueIdentifier != nil }
            ?? identifiers.first)?.text

        let language = element.elements(named: "language").map(\.text).first { !$0.isEmpty }
        return EPUBMetadata(title: title, authors: authors, language: language,
                            identifier: identifier?.isEmpty == true ? nil : identifier)
    }
}
