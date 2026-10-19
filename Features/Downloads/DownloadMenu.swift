import SwiftUI

/// A download's menu: the one definition the Downloads list's rows show from their ⋯ and their
/// long press, the same rows in every section (DR-09):
///
/// | Row | Shows |
/// |---|---|
/// | Pause / Resume | dimmed once done |
/// | Re-download | dimmed while queued |
/// | Keep | dimmed unless its audio is in another voice than downloads now use |
/// | Remove Download (red) | always |
///
/// *Remove Download* is the page menu's own: the audio goes, and the page or folder stays out of
/// downloads until asked again.
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
                    icon: isPaused ? Icons.download : Icons.pause,
                    availability: MenuAvailability(when: isQueued)) { downloads.setPaused(id, !isPaused) },
            MenuRow(id: "menuRedownload", title: Verbs.redownload, icon: Icons.redownload,
                    availability: MenuAvailability(when: !isQueued)) { downloads.redownload(id) },
            MenuRow(id: "menuKeep", title: Verbs.keep, icon: Icons.keep,
                    availability: MenuAvailability(when: otherVoice != nil)) {
                if let otherVoice { downloads.keep(id, voice: otherVoice) }
            },
            MenuRow(id: "menuRemoveDownload", title: Verbs.removeDownload, icon: Icons.removeDownload,
                    isDestructive: true) { downloads.remove(id) },
        ]
    }
}
