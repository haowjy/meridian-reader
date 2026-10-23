import UIKit
import UniformTypeIdentifiers

/// Minimal Share Extension: accept a web URL or a PDF/EPUB file, write it to the App Group
/// inbox, try to open the host app, then dismiss. No editing UI — crude but real.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.text = String(localized: "Opening in Meridian Reader…")
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { await process() }
    }

    private func process() async {
        do {
            try await enqueueSharedItems()
            openHost()
            finish()
        } catch {
            statusLabel.text = String(localized: "Couldn't share to Meridian Reader")
            // Brief pause so the user can read the error, then dismiss.
            try? await Task.sleep(nanoseconds: 800_000_000)
            finish(cancel: true)
        }
    }

    private func enqueueSharedItems() async throws {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            throw ShareError.noItems
        }
        var enqueued = false
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try await loadURL(from: provider) {
                        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                            try SharedInbox.enqueueWebURL(url)
                            enqueued = true
                            return
                        }
                        if url.isFileURL, SharedInbox.isBookFileURL(url) {
                            try SharedInbox.enqueueBookFile(at: url)
                            enqueued = true
                            return
                        }
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    let url = try await loadFileURL(from: provider, type: UTType.pdf.identifier)
                    try SharedInbox.enqueueBookFile(at: url)
                    enqueued = true
                    return
                }
                let epubID = "org.idpf.epub-container"
                if provider.hasItemConformingToTypeIdentifier(epubID) {
                    let url = try await loadFileURL(from: provider, type: epubID)
                    try SharedInbox.enqueueBookFile(at: url)
                    enqueued = true
                    return
                }
                // Files app sometimes offers public.data / public.file-url for .epub/.pdf.
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = try await loadURL(from: provider), url.isFileURL, SharedInbox.isBookFileURL(url) {
                        try SharedInbox.enqueueBookFile(at: url)
                        enqueued = true
                        return
                    }
                }
            }
        }
        if !enqueued { throw ShareError.unsupported }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let string = String(data: data, encoding: .utf8),
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareError.noItems)
                    return
                }
                // loadFileRepresentation's URL is temporary; SharedInbox copies it before return.
                do {
                    // Copy into a stable temp before the completion handler returns (system may delete).
                    let temp = FileManager.default.temporaryDirectory
                        .appending(path: "MeridianShare-\(UUID().uuidString)", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                    let dest = temp.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
                    try FileManager.default.copyItem(at: url, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Share Extensions can't always use `extensionContext.open`; walk the responder chain for
    /// `UIApplication.open`, and fall back to the host draining on next activation.
    private func openHost() {
        let url = SharedInbox.openInboxURL()
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            // Selector openURL: on responders (UIApplication in the chain on some iOS versions).
            if current.responds(to: Selector(("openURL:"))) {
                current.perform(Selector(("openURL:")), with: url)
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }

    private func finish(cancel: Bool = false) {
        if cancel {
            extensionContext?.cancelRequest(withError: ShareError.cancelled)
        } else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private enum ShareError: Error {
        case noItems
        case unsupported
        case cancelled
    }
}
