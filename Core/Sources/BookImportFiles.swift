import Foundation

/// Where a book's file waits while it is imported: `Application Support/Imports/`. A picked file
/// is copied in under its security-scoped access, and a prepared one is saved there, so the
/// import never reads a file it doesn't own. Each file sits in a folder of its own, under its
/// own name (a book with no title in its package is named after its file). The import deletes
/// it when it ends, however it ends; launch clears whatever a killed import left.
struct BookImportFiles {
    let directory: URL

    static let standard = BookImportFiles(directory: AppDirectories.imports)

    /// A copy of the file the picker gave (`url`, security-scoped or not). A copy that fails
    /// leaves nothing here.
    func copyIn(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = try newFile(named: url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            discard(destination)
            throw error
        }
        return destination
    }

    /// A place for a file named `name` (a prepare's suggested name): its folder exists, the file
    /// doesn't yet.
    func newFile(named name: String) throws -> URL {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: Self.fileName(name), directoryHint: .notDirectory)
    }

    /// Deletes `file` and its folder, when it is one of these.
    func discard(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// At launch: no import is running, so every file here is left over.
    func clearLeftovers() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `name` as a file name: keeps `.epub` / `.pdf`, else appends `.epub`. No path separators,
    /// never empty.
    static func fileName(_ name: String) -> String {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasPrefix(".") { base = String(base.drop { $0 == "." }) }
        if base.isEmpty { base = "Imported" }
        let lower = base.lowercased()
        if lower.hasSuffix(".epub") || lower.hasSuffix(".pdf") { return base }
        return base + ".epub"
    }
}
