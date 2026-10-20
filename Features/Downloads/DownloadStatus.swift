import SwiftUI

/// What a download still to finish says about itself, the one wording a folder header and the
/// Downloads list share (C91): where it is and how long its rendering has left, then why it can
/// take a while.
///
/// ```
/// Downloading 5 of 17   ~2 h 45 min left
/// Downloads while Meridian is open
/// ```
enum DownloadStatusText {
    /// "Downloads while Meridian is open": rendering runs only with the app on screen.
    static var whileOpen: String { String(localized: "Downloads while Meridian is open") }

    /// A download's line: ["Downloading 5 of 17", "~2 h 45 min left"], ["Waiting 5 of 17",
    /// "starts in ~3 h"], ["Paused 5 of 17"]. `count`: show "5 of 17" (a folder's); a page's
    /// download shows only its state and time.
    @MainActor
    static func parts(_ record: DownloadRecord, downloads: DownloadCenter, count: Bool) -> [String] {
        let of = count ? " \(record.finishedCount) of \(record.entries.count)" : ""
        if record.isPaused { return [String(localized: "Paused\(of)")] }
        let left = downloads.renderSecondsLeft(record).map { String(localized: "\(DownloadCenter.estimate($0)) left") }
        if downloads.isActive(record.id) {
            return [String(localized: "Downloading\(of)"), left].compactMap { $0 }
        }
        let before = downloads.renderSecondsBefore(record)
        return [String(localized: "Waiting\(of)"),
                before > 0 ? String(localized: "starts in \(DownloadCenter.estimate(before))") : left].compactMap { $0 }
    }
}

/// A folder header's download status (`FolderHeader`'s `status`), while its download has pages
/// still to render: "Downloading 5 of 17   ~2 h 45 min left", then "Downloads while Meridian is
/// open" (not while paused). Nothing otherwise.
struct FolderDownloadStatus: View {
    let folder: Folder

    @Environment(DownloadCenter.self) private var downloads

    var body: some View {
        if let record = downloads.record(for: .folder(folder.id)), record.hasQueuedPages {
            VStack(spacing: Spacing.xxs) {
                DetailLine(DownloadStatusText.parts(record, downloads: downloads, count: true))
                    .monospacedDigit()
                if !record.isPaused { DetailLine([DownloadStatusText.whileOpen]) }
            }
            .typeStyle(.caption)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("folderDownloadStatus")
        }
    }
}
