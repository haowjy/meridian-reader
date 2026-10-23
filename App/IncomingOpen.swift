import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Open In / Share entry: document URLs the system hands the app, `meridian-reader://inbox` from
/// the Share Extension, and a drain of the App Group inbox whenever the app becomes active.
///
/// - http(s) → Browse (`ShellState.navigate`)
/// - PDF / EPUB file → same path as Library *Import from…* (`BookImportActions.importPicked`)
/// - `meridian-reader://inbox` → drain `SharedInbox` (URLs and files the Share Extension wrote)
@MainActor
enum IncomingOpen {
    /// Handles a URL the system or Share Extension opened the app with.
    static func handle(_ url: URL, library: LibraryStore, shell: ShellState) {
        if SharedInbox.isInboxURL(url) {
            drainInbox(library: library, shell: shell)
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            shell.navigate(to: url)
            return
        }
        if url.isFileURL {
            openBookFile(url, library: library, shell: shell)
            return
        }
        // Unknown custom URL: ignore (don't toast — cold-start noise).
        library.log("openURL: ignored \(url.absoluteString)")
    }

    /// Drains anything the Share Extension left in the App Group. Safe to call often.
    static func drainInbox(library: LibraryStore, shell: ShellState) {
        let items = SharedInbox.drain()
        guard !items.isEmpty else { return }
        for item in items {
            switch item.kind {
            case .webURL:
                if let string = item.urlString, let url = URL(string: string),
                   let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    shell.navigate(to: url)
                } else {
                    library.log("inbox: bad web URL \(item.urlString ?? "nil")")
                }
            case .bookFile:
                if let file = SharedInbox.fileURL(for: item) {
                    // Import copies into Application Support; discard the group copy after.
                    BookImportActions(library: library, shell: shell).importPicked(file, into: nil)
                    SharedInbox.discardFile(for: item)
                } else {
                    library.log("inbox: missing file for \(item.fileName ?? item.id.uuidString)")
                }
            }
        }
    }

    private static func openBookFile(_ url: URL, library: LibraryStore, shell: ShellState) {
        guard SharedInbox.isBookFileURL(url) || SharedInbox.isBookFileName(url.lastPathComponent) else {
            library.log("openURL: not a book file \(url.lastPathComponent)")
            shell.showToast(ShellToast(message: String(localized: "Meridian can open PDF and EPUB files"),
                                       systemImage: Icons.warning))
            return
        }
        BookImportActions(library: library, shell: shell).importPicked(url, into: nil)
    }
}

/// Attaches Open In / Share handling to the root scene: `onOpenURL`, and a drain when the scene
/// becomes active (Share Extension may have written the inbox without successfully opening us).
struct IncomingOpenModifier: ViewModifier {
    let library: LibraryStore
    let shell: ShellState
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onOpenURL { IncomingOpen.handle($0, library: library, shell: shell) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    IncomingOpen.drainInbox(library: library, shell: shell)
                }
            }
            .onAppear {
                IncomingOpen.drainInbox(library: library, shell: shell)
            }
    }
}
