import SwiftUI

/// A download's menu: the one definition the Downloads list's rows show from their ⋯ and their
/// long press, the same rows in every section (DR-09):
///
/// | Row | Shows |
/// |---|---|
/// | Pause / Resume | dimmed once done |
/// | Re-download | dimmed while queued |
/// | Keep | dimmed unless its audio is in another voice than downloads now use |
/// | Remove Download / Remove Downloads (red) | always |
///
/// The remove row (and the row's swipe) is the item's own: a page's *Remove Download*, a folder's
/// *Remove Downloads*, the same action as in the page's or folder's menu (`DownloadCenter.remove`).
struct DownloadMenu: View {
    let item: DownloadOverview.Item
    let downloads: DownloadCenter

    var body: some View {
        MenuRows(rows)
    }

    var rows: [MenuRow] {
        let id = item.id
        let isQueued = item.status.fraction != nil
        let isPaused = item.record.isPaused
        let otherVoice: String? = if case .differentVoice(let voice) = item.status { voice } else { nil }
        return [
            MenuRow(id: "menuPause", title: isPaused ? Verbs.resume : Verbs.pause,
                    icon: isPaused ? Icons.resume : Icons.pause,
                    availability: MenuAvailability(when: isQueued)) { downloads.setPaused(id, !isPaused) },
            MenuRow(id: "menuRedownload", title: Verbs.redownload, icon: Icons.redownload,
                    availability: MenuAvailability(when: !isQueued)) { downloads.redownload(id) },
            MenuRow(id: "menuKeep", title: Verbs.keep, icon: Icons.keep,
                    availability: MenuAvailability(when: otherVoice != nil)) {
                if let otherVoice { downloads.keep(id, voice: otherVoice) }
            },
            MenuRow(id: "menuRemoveDownload", title: Self.removeTitle(item), icon: Icons.removeDownload,
                    isDestructive: true) { downloads.remove(id) },
        ]
    }

    /// *Remove Download* for a page, *Remove Downloads* for a folder: the name its own menu gives it.
    static func removeTitle(_ item: DownloadOverview.Item) -> String {
        item.record.target.isFolder ? Verbs.removeDownloads : Verbs.removeDownload
    }
}
