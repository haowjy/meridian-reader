import Foundation

/// Books refused before any text is read: copy-protected ones and fixed-layout ones.
enum EPUBRefusals {
    /// Rights files that only DRM schemes write: Adobe ADEPT, Readium LCP, Apple FairPlay.
    static let rightsFiles = ["META-INF/rights.xml", "META-INF/license.lcpl", "license.lcpl", "META-INF/sinf.xml"]
    static let encryptionPath = "META-INF/encryption.xml"
    static let appleDisplayOptionsPath = "META-INF/com.apple.ibooks.display-options.xml"

    static func checkRightsFiles(in archive: EPUBArchive) throws {
        if rightsFiles.contains(where: archive.contains) { throw EPUBError.drmProtected }
    }

    /// DRM: `encryption.xml` lists a document the text is read from (a spine document, the nav,
    /// the NCX). Obfuscated fonts (IDPF's and Adobe's font algorithms) and other encrypted
    /// resources are fine: the text never needs them.
    /// Fixed layout: `rendition:layout` pre-paginated, or Apple's display options say so.
    static func check(_ package: EPUBPackage, in archive: EPUBArchive) throws {
        if archive.contains(encryptionPath) {
            guard let encryption = XMLTree.parse(try archive.data(at: encryptionPath)) else {
                throw EPUBError.unreadable("encryption.xml isn't readable")
            }
            let textDocuments = Set(
                (package.spine.map(\.path) + [package.navPath, package.ncxPath].compactMap { $0 })
                    .map { $0.lowercased() }
            )
            for reference in encryption.descendants(named: "cipherreference") {
                guard let uri = reference.attribute("URI"),
                      let resolved = EPUBPath.resolve(uri, relativeTo: "") else { continue }
                let path = archive.entryPath(matching: resolved.path) ?? resolved.path
                if textDocuments.contains(path.lowercased()) { throw EPUBError.drmProtected }
            }
        }
        if package.isPrePaginated { throw EPUBError.fixedLayout }
        if archive.contains(appleDisplayOptionsPath),
           let options = XMLTree.parse(try archive.data(at: appleDisplayOptionsPath)) {
            let fixed = options.descendants(named: "option").contains {
                $0.attribute("name")?.lowercased() == "fixed-layout" && $0.text.lowercased() == "true"
            }
            if fixed { throw EPUBError.fixedLayout }
        }
    }
}
