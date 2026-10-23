import Foundation
import UniformTypeIdentifiers

/// App Group hand-off from the Share Extension (and a place Open In can stage files) into the
/// host app. The extension writes a pending item under `Inbox/`, then asks the host to open
/// `meridian-reader://inbox`. The host drains on that URL and whenever it becomes active.
///
/// Bundle id suffix (probe installs) is part of the group id so the probe app never shares an
/// inbox with the release app.
enum SharedInbox {
    /// Custom scheme the Share Extension opens so the host drains this inbox.
    static let scheme = "meridian-reader"
    static let inboxHost = "inbox"

    /// `group.com.jimmyyao.Reader` or `group.com.jimmyyao.Reader.probe` when `BUNDLE_ID_SUFFIX` is set.
    static var appGroupID: String {
        let suffix = Bundle.main.object(forInfoDictionaryKey: "MeridianAppGroupSuffix") as? String ?? ""
        return "group.com.jimmyyao.Reader\(suffix)"
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var inboxDirectory: URL? {
        containerURL?.appending(path: "Inbox", directoryHint: .isDirectory)
    }

    /// One pending hand-off. Files live beside the JSON under `Inbox/files/<uuid>/`.
    struct Item: Codable, Equatable {
        enum Kind: String, Codable {
            /// An http(s) page URL to open in Browse.
            case webURL
            /// A PDF or EPUB file to run through `BookImportActions`.
            case bookFile
        }

        var id: UUID
        var kind: Kind
        /// Absolute http(s) URL string when `kind == .webURL`.
        var urlString: String?
        /// Path relative to the App Group container when `kind == .bookFile`.
        var relativeFilePath: String?
        var fileName: String?
        var createdAt: Date
    }

    // MARK: - Write (Share Extension)

    /// Enqueues an http(s) URL for Browse.
    static func enqueueWebURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw InboxError.unsupportedURL
        }
        var item = Item(id: UUID(), kind: .webURL, urlString: url.absoluteString, relativeFilePath: nil,
                        fileName: nil, createdAt: Date())
        try write(item)
    }

    /// Copies `fileURL` (security-scoped or not) into the group and enqueues a book import.
    static func enqueueBookFile(at fileURL: URL) throws {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        let name = fileURL.lastPathComponent
        guard isBookFileName(name) else { throw InboxError.unsupportedFile }

        let inbox = try preparedInbox()
        let folder = inbox.appending(path: "files/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: sanitizedFileName(name), directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fileURL, to: destination)

        guard let container = containerURL else { throw InboxError.noAppGroup }
        let relative = destination.path.replacingOccurrences(of: container.path + "/", with: "")
        let item = Item(id: UUID(), kind: .bookFile, urlString: nil, relativeFilePath: relative,
                        fileName: name, createdAt: Date())
        try write(item)
    }

    // MARK: - Read (host app)

    /// Pending items oldest-first, then removes their JSON (files stay until the host discards them).
    static func drain() -> [Item] {
        guard let inbox = inboxDirectory else { return [] }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let jsons = urls.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }

        var items: [Item] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in jsons {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let item = try? decoder.decode(Item.self, from: data) else { continue }
            items.append(item)
        }
        return items
    }

    /// Absolute file URL for a drained book item, if the file is still there.
    static func fileURL(for item: Item) -> URL? {
        guard item.kind == .bookFile, let relative = item.relativeFilePath, let container = containerURL else {
            return nil
        }
        let url = container.appending(path: relative, directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Deletes a drained book file and its folder once import has copied it (or failed).
    static func discardFile(for item: Item) {
        guard let url = fileURL(for: item) else { return }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folder)
    }

    static func openInboxURL() -> URL {
        URL(string: "\(scheme)://\(inboxHost)")!
    }

    static func isInboxURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == inboxHost
    }

    static func isBookFileName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".epub") || lower.hasSuffix(".pdf")
    }

    static func isBookFileURL(_ url: URL) -> Bool {
        if isBookFileName(url.lastPathComponent) { return true }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) { return true }
            if type.identifier == "org.idpf.epub-container" { return true }
            if type.conforms(to: UTType(filenameExtension: "epub") ?? .data) && url.pathExtension.lowercased() == "epub" {
                return true
            }
        }
        return false
    }

    // MARK: - Private

    private static func preparedInbox() throws -> URL {
        guard let inbox = inboxDirectory else { throw InboxError.noAppGroup }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    private static func write(_ item: Item) throws {
        let inbox = try preparedInbox()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(item)
        let url = inbox.appending(path: "\(item.id.uuidString).json", directoryHint: .notDirectory)
        try data.write(to: url, options: .atomic)
    }

    private static func sanitizedFileName(_ name: String) -> String {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Imported" }
        return base
    }

    enum InboxError: Error {
        case noAppGroup
        case unsupportedURL
        case unsupportedFile
    }
}
