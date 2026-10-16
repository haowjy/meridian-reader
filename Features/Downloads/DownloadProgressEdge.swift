import SwiftUI

/// The progress line on a surface's bottom chrome (the browser's, the Library's, the Reader's,
/// Now Playing's), a `ProgressLine` on the edge track:
/// shown while downloads run, gone when nothing is queued, everything queued is paused, or no
/// on-device voice renders downloads (decision D16). Laid over the top edge of the band
/// (`.overlay(alignment: .top)`); it always takes the band's width and the line's height, so a
/// toast laid beside it keeps its place. VoiceOver reads it as a button that opens Downloads.
struct DownloadProgressEdge: View {
    @Environment(DownloadCenter.self) private var downloads
    @Environment(ShellState.self) private var shell

    var body: some View {
        let progress = downloads.progress
        ZStack {
            if let progress {
                ProgressLine(fraction: progress, height: ProgressLine.edgeHeight, track: .edge)
                    .animation(Motion.standard, value: progress)
                    .transition(.opacity)
                    .accessibilityElement()
                    .accessibilityLabel("Downloads")
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
                    .accessibilityHint("Opens Downloads")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { shell.present(.downloads) }
                    .accessibilityIdentifier("downloadProgress")
            }
        }
        .frame(maxWidth: .infinity, minHeight: ProgressLine.edgeHeight, maxHeight: ProgressLine.edgeHeight)
        .animation(Motion.snappy, value: progress == nil)
    }
}

/// Asking for a download from a row's menu or a ⋯ panel: the request, then a toast saying what
/// happened, with *Show* to open Downloads.
@MainActor
struct DownloadActions {
    let downloads: DownloadCenter
    let shell: ShellState

    func download(_ page: Page) {
        report(downloads.download(page), title: page.title)
    }

    func download(_ folder: Folder) {
        report(downloads.download(folder), title: folder.name)
    }

    private func report(_ request: DownloadCenter.Request, title: String) {
        let message: String
        switch request {
        case .added, .resumed: message = String(localized: "Downloading “\(title)”")
        case .alreadyQueued: message = String(localized: "“\(title)” is already downloading")
        case .nothingToDownload:
            shell.showToast(ShellToast(message: String(localized: "Nothing to download"), systemImage: Icons.download))
            return
        }
        shell.showToast(ShellToast(message: message, systemImage: Icons.download, actionTitle: String(localized: "Show")) {
            [shell] in shell.present(.downloads)
        })
    }
}
